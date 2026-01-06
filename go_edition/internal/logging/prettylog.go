package logging

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"sync"
)

const (
	timeFormat = "[15:04:05.000]"

	reset = "\033[0m"

	black        = 30
	red          = 31
	green        = 32
	yellow       = 33
	blue         = 34
	magenta      = 35
	cyan         = 36
	lightGray    = 37
	darkGray     = 90
	lightRed     = 91
	lightGreen   = 92
	lightYellow  = 93
	lightBlue    = 94
	lightMagenta = 95
	lightCyan    = 96
	white        = 97
)

func colorizer(colorCode int, v string) string {
	return fmt.Sprintf("\033[%sm%s%s", strconv.Itoa(colorCode), v, reset)
}

type PrettyHandler struct {
	h        slog.Handler
	r        func([]string, slog.Attr) slog.Attr
	b        *bytes.Buffer
	m        *sync.Mutex
	writer   io.Writer
	colorize bool
}

func (h *PrettyHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.h.Enabled(ctx, level)
}

func (h *PrettyHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &PrettyHandler{h: h.h.WithAttrs(attrs), b: h.b, r: h.r, m: h.m, writer: h.writer, colorize: h.colorize}
}

func (h *PrettyHandler) WithGroup(name string) slog.Handler {
	return &PrettyHandler{h: h.h.WithGroup(name), b: h.b, r: h.r, m: h.m, writer: h.writer, colorize: h.colorize}
}

func (h *PrettyHandler) computeAttrs(
	ctx context.Context,
	r slog.Record,
) (map[string]any, error) {
	h.m.Lock()
	defer func() {
		h.b.Reset()
		h.m.Unlock()
	}()
	if err := h.h.Handle(ctx, r); err != nil {
		return nil, fmt.Errorf("error when calling inner handler's Handle: %w", err)
	}

	var attrs map[string]any
	err := json.Unmarshal(h.b.Bytes(), &attrs)
	if err != nil {
		return nil, fmt.Errorf("error when unmarshaling inner handler's Handle result: %w", err)
	}
	return attrs, nil
}

func (h *PrettyHandler) Handle(ctx context.Context, r slog.Record) error {
	colorize := func(code int, value string) string {
		return value
	}
	if h.colorize {
		colorize = colorizer
	}

	var level string
	levelAttr := slog.Attr{
		Key:   slog.LevelKey,
		Value: slog.AnyValue(r.Level),
	}
	if h.r != nil {
		levelAttr = h.r([]string{}, levelAttr)
	}

	if !levelAttr.Equal(slog.Attr{}) {
		level = levelAttr.Value.String() + ":"

		if r.Level <= slog.LevelDebug {
			level = colorize(lightGray, level)
		} else if r.Level <= slog.LevelInfo {
			level = colorize(cyan, level)
		} else if r.Level < slog.LevelWarn {
			level = colorize(lightBlue, level)
		} else if r.Level < slog.LevelError {
			level = colorize(lightYellow, level)
		} else if r.Level <= slog.LevelError+1 {
			level = colorize(lightRed, level)
		} else if r.Level > slog.LevelError+1 {
			level = colorize(lightMagenta, level)
		}
	}

	var timestamp string
	timeAttr := slog.Attr{
		Key:   slog.TimeKey,
		Value: slog.StringValue(r.Time.Format(timeFormat)),
	}
	if h.r != nil {
		timeAttr = h.r([]string{}, timeAttr)
	}
	if !timeAttr.Equal(slog.Attr{}) {
		timestamp = colorize(lightGray, timeAttr.Value.String())
	}

	var msg string
	msgAttr := slog.Attr{
		Key:   slog.MessageKey,
		Value: slog.StringValue(r.Message),
	}
	if h.r != nil {
		msgAttr = h.r([]string{}, msgAttr)
	}
	if !msgAttr.Equal(slog.Attr{}) {
		msg = colorize(white, msgAttr.Value.String())
	}

	attrs, err := h.computeAttrs(ctx, r)
	if err != nil {
		return err
	}
	bytes, err := json.MarshalIndent(attrs, "", "  ")
	if err != nil {
		return fmt.Errorf("error when marshaling attrs: %w", err)
	}

	out := strings.Builder{}
	if len(timestamp) > 0 {
		out.WriteString(timestamp)
		out.WriteString(" ")
	}
	if len(level) > 0 {
		out.WriteString(level)
		out.WriteString(" ")
	}
	if len(msg) > 0 {
		out.WriteString(msg)
		out.WriteString(" ")
	}
	if len(bytes) > 0 {
		out.WriteString(colorize(darkGray, string(bytes)))
	}

	_, err = io.WriteString(h.writer, out.String()+"\n")
	if err != nil {
		return err
	}

	return nil
}

func suppressDefaults(
	next func([]string, slog.Attr) slog.Attr,
) func([]string, slog.Attr) slog.Attr {
	return func(groups []string, a slog.Attr) slog.Attr {
		if a.Key == slog.TimeKey ||
			a.Key == slog.LevelKey ||
			a.Key == slog.MessageKey {
			return slog.Attr{}
		}
		if next == nil {
			return a
		}
		return next(groups, a)
	}
}

func NewPrettyHandler(handlerOptions *slog.HandlerOptions, options ...PrettyOption) *PrettyHandler {
	if handlerOptions == nil {
		handlerOptions = &slog.HandlerOptions{}
	}

	buf := &bytes.Buffer{}
	handler := &PrettyHandler{
		b: buf,
		h: slog.NewJSONHandler(buf, &slog.HandlerOptions{
			Level:       handlerOptions.Level,
			AddSource:   handlerOptions.AddSource,
			ReplaceAttr: suppressDefaults(handlerOptions.ReplaceAttr),
		}),
		r: handlerOptions.ReplaceAttr,
		m: &sync.Mutex{},
	}

	for _, opt := range options {
		opt(handler)
	}

	return handler
}

func NewPrettyLoggingHandler(opts *slog.HandlerOptions) *PrettyHandler {
	return NewPrettyHandler(opts, WithDestinationWriter(os.Stdout), WithColor())
}

type PrettyOption func(h *PrettyHandler)

func WithDestinationWriter(writer io.Writer) PrettyOption {
	return func(h *PrettyHandler) {
		h.writer = writer
	}
}

func WithColor() PrettyOption {
	return func(h *PrettyHandler) {
		h.colorize = true
	}
}
