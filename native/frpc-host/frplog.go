package main

import (
	"io"
	"strings"
	"time"

	goliblog "github.com/fatedier/golib/log"
	frlog "github.com/fatedier/frp/pkg/util/log"
)

// frpTSVWriter adapts frp's internal logger onto the app's TSV log store.
// golib's Logger dispatches through WriteLog when the output implements it,
// which preserves the per-entry level.
type frpTSVWriter struct {
	logger *tsvLogger
}

var _ io.Writer = frpTSVWriter{}
var _ goliblog.Writer = frpTSVWriter{}

func (w frpTSVWriter) Write(p []byte) (int, error) {
	w.logger.Logf("INFO", "%s", strings.TrimSpace(string(p)))
	return len(p), nil
}

func (w frpTSVWriter) WriteLog(p []byte, level goliblog.Level, when time.Time) (int, error) {
	w.logger.Logf(golibLevelName(level), "%s", strings.TrimSpace(string(p)))
	return len(p), nil
}

func golibLevelName(level goliblog.Level) string {
	switch level {
	case goliblog.TraceLevel:
		return "DEBUG"
	case goliblog.DebugLevel:
		return "DEBUG"
	case goliblog.WarnLevel:
		return "WARN"
	case goliblog.ErrorLevel:
		return "ERROR"
	default:
		return "INFO"
	}
}

// installFrpLogger routes all frp log lines into the per-config TSV log file.
func installFrpLogger(logger *tsvLogger, levelStr string) {
	level, err := goliblog.ParseLevel(strings.TrimSpace(levelStr))
	if err != nil {
		level = goliblog.InfoLevel
	}
	frlog.Logger = frlog.Logger.WithOptions(
		goliblog.WithOutput(frpTSVWriter{logger: logger}),
		goliblog.WithLevel(level),
	)
}

// main is required by -buildmode=c-shared but never runs; the OHOS runtime
// enters through the exported Main symbol instead.
func main() {}
