package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// tsvLogger appends FrpLogStore-compatible lines ("<ms>\t<LEVEL>\t<msg>\n")
// to the per-config log file shared with the ArkTS side.
type tsvLogger struct {
	mu sync.Mutex
	f  *os.File
}

func newTSVLogger(path string) *tsvLogger {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return &tsvLogger{}
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return &tsvLogger{}
	}
	return &tsvLogger{f: f}
}

func (l *tsvLogger) Logf(level, format string, args ...any) {
	if l == nil || l.f == nil {
		return
	}
	msg := fmt.Sprintf(format, args...)
	msg = strings.ReplaceAll(msg, "\r", "\\r")
	msg = strings.ReplaceAll(msg, "\n", "\\n")
	line := fmt.Sprintf("%d\t%s\t%s\n", time.Now().UnixMilli(), level, msg)
	l.mu.Lock()
	defer l.mu.Unlock()
	l.f.WriteString(line)
}

func (l *tsvLogger) Close() {
	if l == nil || l.f == nil {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	l.f.Sync()
	l.f.Close()
	l.f = nil
}
