// libfrp_host — frpc host library for HarmonyOS native child processes.
//
// The app loads this library through childProcessManager.startNativeChildProcess
// with entry point "libfrp_host.so:Main". The entry function receives the
// JSON-encoded EntryParams string and runs one frpc instance in-process.
// The child has no IPC channel back to the app, so all coordination flows
// through files inside the shared sandbox:
//
//	<ctlDir>/<base>.stop   — presence requests a graceful stop
//	<ctlDir>/<base>.exit   — written once on exit: {"code":N,"message":"..."}
//	<ctlDir>/<base>.pid    — liveness marker for orphan cleanup
//
// Exit codes reported through the .exit file:
//
//	0 normal stop, 1 runtime error, 2 config load/validation error,
//	3 bad host parameters, 4 internal panic.
package main

/*
#include <stdlib.h>

// Mirrors AbilityKit/native_child_process.h (API 13). The system dlsym()s the
// entry symbol and calls it by value with these structs, so the layout here
// must match the SDK header exactly.
typedef struct NativeChildProcess_Fd {
	char* fdName;
	int fd;
	struct NativeChildProcess_Fd* next;
} NativeChildProcess_Fd;

typedef struct NativeChildProcess_FdList {
	struct NativeChildProcess_Fd* head;
} NativeChildProcess_FdList;

typedef struct NativeChildProcess_Args {
	char* entryParams;
	NativeChildProcess_FdList fdList;
} NativeChildProcess_Args;
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/fatedier/frp/client"
	"github.com/fatedier/frp/pkg/config"
	"github.com/fatedier/frp/pkg/config/source"
	"github.com/fatedier/frp/pkg/config/v1/validation"
	"github.com/fatedier/frp/pkg/policy/security"
	"github.com/fatedier/frp/pkg/util/version"
)

// EntryParams is the JSON contract with the ArkTS FrpRuntimeAdapter. The app
// resolves every path so this host never derives locations on its own.
type EntryParams struct {
	Type       string `json:"type"`       // only "frpc" is bundled
	ConfigId   string `json:"configId"`   // e.g. "frpc:web.toml"
	ConfigPath string `json:"configPath"` // absolute TOML path
	LogPath    string `json:"logPath"`    // FrpLogStore TSV file
	CtlDir     string `json:"ctlDir"`     // control files directory
	Mode       string `json:"mode"`       // "child" (own process) or "inline" (in-app goroutine)
	Version    int    `json:"version"`    // contract version, currently 1
}

// ExitReport is the JSON payload written to <base>.exit exactly once.
type ExitReport struct {
	Code      int    `json:"code"`
	Message   string `json:"message"`
	Pid       int    `json:"pid"`
	StartedAt int64  `json:"startedAt"`
	StoppedAt int64  `json:"stoppedAt"`
}

// Main is the native child-process entry required by the OHOS runtime.
//
//export Main
func Main(args C.NativeChildProcess_Args) {
	paramsJSON := ""
	if args.entryParams != nil {
		paramsJSON = C.GoString(args.entryParams)
	}
	runHost(paramsJSON)
}

// FrpHostRun is the in-process entry used when the device cannot spawn native
// child processes; the NAPI glue in frp_napi.cpp dlsym()s it from the UI
// process. It runs one frpc instance on a goroutine and returns immediately.
//
//export FrpHostRun
func FrpHostRun(paramsJSON *C.char) C.int {
	if paramsJSON == nil {
		return 3
	}
	go runHost(C.GoString(paramsJSON))
	return 0
}

func runHost(paramsJSON string) {
	startedAt := time.Now()
	code := 0
	message := ""
	var params EntryParams

	defer func() {
		if r := recover(); r != nil {
			code = 4
			message = fmt.Sprintf("frp host panic: %v", r)
		}
		writeExitReport(params, code, message, os.Getpid(), startedAt)
	}()

	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		code = 3
		message = fmt.Sprintf("invalid entry params: %v", err)
		return
	}
	if params.Type != "frpc" {
		code = 3
		message = fmt.Sprintf("unsupported type %q: this core only bundles frpc", params.Type)
		return
	}
	if params.ConfigPath == "" || params.LogPath == "" || params.CtlDir == "" {
		code = 3
		message = "entry params missing configPath/logPath/ctlDir"
		return
	}

	base := ctlBaseName(params.ConfigId)
	stopFile := filepath.Join(params.CtlDir, base+".stop")
	exitFile := filepath.Join(params.CtlDir, base+".exit")
	pidFile := filepath.Join(params.CtlDir, base+".pid")

	logger := newTSVLogger(params.LogPath)
	// Inline mode also clears an orphaned child instance, but never writes a
	// pid marker: the marker must only ever hold a dedicated child pid.
	killOrphanInstance(logger, pidFile)
	if params.Mode != "inline" {
		if err := os.WriteFile(pidFile, []byte(strconv.Itoa(os.Getpid())), 0o600); err != nil {
			code = 3
			message = fmt.Sprintf("write pid file failed: %v", err)
			return
		}
		defer os.Remove(pidFile)
	}
	os.Remove(stopFile)
	os.Remove(exitFile)

	logger.Logf("INFO", "frp host started (pid %d, core frp %s)", os.Getpid(), frpVersion())

	err := runFrpc(logger, params, stopFile)
	if err != nil {
		code = 1
		message = err.Error()
		logger.Logf("ERROR", "frpc exited with error: %s", message)
	} else {
		logger.Logf("INFO", "frp host stopped normally")
	}
}

// runFrpc mirrors the official cmd/frpc startup sequence with the config file
// as the single source, plus a stop-file watcher that triggers a graceful close.
func runFrpc(logger *tsvLogger, params EntryParams, stopFile string) error {
	result, err := config.LoadClientConfigResult(params.ConfigPath, false)
	if err != nil {
		logger.Logf("ERROR", "load config failed: %s", err)
		return fmt.Errorf("config error: %w", err)
	}

	configSource := source.NewConfigSource()
	if err := configSource.ReplaceAll(result.Proxies, result.Visitors); err != nil {
		return fmt.Errorf("config source error: %w", err)
	}
	aggregator := source.NewAggregator(configSource)

	proxyCfgs, visitorCfgs, err := aggregator.Load()
	if err != nil {
		return fmt.Errorf("config load error: %w", err)
	}
	proxyCfgs, visitorCfgs = config.FilterClientConfigurers(result.Common, proxyCfgs, visitorCfgs)
	proxyCfgs = config.CompleteProxyConfigurers(proxyCfgs)
	visitorCfgs = config.CompleteVisitorConfigurers(visitorCfgs)

	unsafeFeatures := security.NewUnsafeFeatures(nil)
	if _, err := validation.ValidateAllClientConfig(result.Common, proxyCfgs, visitorCfgs, unsafeFeatures); err != nil {
		logger.Logf("ERROR", "validate config failed: %s", err)
		return fmt.Errorf("config error: %w", err)
	}

	// Route every frp log line into the app's TSV log store.
	installFrpLogger(logger, result.Common.Log.Level)

	svr, err := client.NewService(client.ServiceOptions{
		Common:                 result.Common,
		ConfigSourceAggregator: aggregator,
		UnsafeFeatures:         unsafeFeatures,
		ConfigFilePath:         params.ConfigPath,
	})
	if err != nil {
		return fmt.Errorf("create service error: %w", err)
	}

	stopCh := watchStopFile(stopFile, 300*time.Millisecond)
	var stopRequested atomic.Bool
	done := make(chan struct{})
	go func() {
		select {
		case <-stopCh:
			stopRequested.Store(true)
			logger.Logf("INFO", "stop requested, closing frpc gracefully")
			svr.GracefulClose(500 * time.Millisecond)
		case <-done:
		}
	}()
	defer close(done)

	err = svr.Run(context.Background())
	// A stop-file shutdown surfaces as an arbitrary error from Run (frp often
	// reports the in-flight login as failed); a user-requested stop is normal.
	if err != nil && stopRequested.Load() {
		logger.Logf("INFO", "frpc closed after stop request (suppressed: %v)", err)
		err = nil
	}
	return err
}

func watchStopFile(stopFile string, interval time.Duration) <-chan struct{} {
	ch := make(chan struct{})
	go func() {
		for {
			if _, err := os.Stat(stopFile); err == nil {
				close(ch)
				return
			}
			time.Sleep(interval)
		}
	}()
	return ch
}

// killOrphanInstance terminates a previous child left behind by a recycled
// runtime (same app uid, so signal delivery is permitted).
func killOrphanInstance(logger *tsvLogger, pidFile string) {
	raw, err := os.ReadFile(pidFile)
	if err != nil {
		return
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil || pid <= 0 || pid == os.Getpid() {
		return
	}
	if e := syscall.Kill(pid, 0); e != nil {
		os.Remove(pidFile) // stale marker, no such process
		return
	}
	logger.Logf("WARN", "stopping orphan frpc instance pid %d", pid)
	syscall.Kill(pid, syscall.SIGTERM)
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if e := syscall.Kill(pid, 0); e != nil {
			os.Remove(pidFile)
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
	syscall.Kill(pid, syscall.SIGKILL)
	time.Sleep(300 * time.Millisecond)
	os.Remove(pidFile)
}

func writeExitReport(params EntryParams, code int, message string, pid int, startedAt time.Time) {
	if params.CtlDir == "" {
		return
	}
	report := ExitReport{
		Code:      code,
		Message:   message,
		Pid:       pid,
		StartedAt: startedAt.UnixMilli(),
		StoppedAt: time.Now().UnixMilli(),
	}
	raw, err := json.Marshal(report)
	if err != nil {
		return
	}
	base := ctlBaseName(params.ConfigId)
	tmp := filepath.Join(params.CtlDir, base+".exit.tmp")
	dst := filepath.Join(params.CtlDir, base+".exit")
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return
	}
	os.Rename(tmp, dst)
}

// ctlBaseName flattens a config id ("frpc:web.toml") into a safe file stem.
// The ArkTS side applies the identical rule.
func ctlBaseName(configId string) string {
	var b strings.Builder
	for _, r := range configId {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') ||
			r == '.' || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	if b.Len() == 0 {
		return "config"
	}
	return b.String()
}

func frpVersion() string {
	return version.Full()
}
