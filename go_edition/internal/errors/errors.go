// Package errors provides custom error types and error handling utilities
// for the Zapret application. It extends Go's standard error handling with
// additional context and typing for better error management.
package errors

import (
	"errors"
	"fmt"
)

// Error types
var (
	ErrConfigValidation  = errors.New("configuration validation failed")
	ErrStrategyParse     = errors.New("strategy parsing failed")
	ErrFirewallSetup     = errors.New("firewall setup failed")
	ErrProcessManagement = errors.New("process management failed")
	ErrService           = errors.New("service operation failed")
	ErrNotFound          = errors.New("resource not found")
	ErrPermissionDenied  = errors.New("permission denied")
	ErrTimeout           = errors.New("operation timed out")
)

// ConfigError represents configuration-related errors
type ConfigError struct {
	BaseError error
	Field     string
	Value     interface{}
	Message   string
}

func (e *ConfigError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("%s: %s (field: %s, value: %v)", e.BaseError, e.Message, e.Field, e.Value)
	}
	return fmt.Sprintf("%s: field %s has invalid value %v", e.BaseError, e.Field, e.Value)
}

func (e *ConfigError) Unwrap() error {
	return e.BaseError
}

func (e *ConfigError) Is(target error) bool {
	return errors.Is(e.BaseError, target)
}

// NewConfigError creates a new configuration error
func NewConfigError(field string, value interface{}, msg string) *ConfigError {
	return &ConfigError{
		BaseError: ErrConfigValidation,
		Field:     field,
		Value:     value,
		Message:   msg,
	}
}

// StrategyError represents strategy parsing errors
type StrategyError struct {
	BaseError error
	File      string
	Line      int
	Message   string
}

func (e *StrategyError) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("%s: %s (file: %s, line: %d)", e.BaseError, e.Message, e.File, e.Line)
	}
	return fmt.Sprintf("%s: %s (file: %s)", e.BaseError, e.Message, e.File)
}

func (e *StrategyError) Unwrap() error {
	return e.BaseError
}

func (e *StrategyError) Is(target error) bool {
	return errors.Is(e.BaseError, target)
}

// NewStrategyError creates a new strategy error
func NewStrategyError(file string, line int, msg string) *StrategyError {
	return &StrategyError{
		BaseError: ErrStrategyParse,
		File:      file,
		Line:      line,
		Message:   msg,
	}
}

// FirewallError represents firewall-related errors
type FirewallError struct {
	BaseError error
	Operation string
	Backend   string
	Message   string
}

func (e *FirewallError) Error() string {
	return fmt.Sprintf("%s: %s (backend: %s, operation: %s)", e.BaseError, e.Message, e.Backend, e.Operation)
}

func (e *FirewallError) Unwrap() error {
	return e.BaseError
}

func (e *FirewallError) Is(target error) bool {
	return errors.Is(e.BaseError, target)
}

// NewFirewallError creates a new firewall error
func NewFirewallError(backend, operation, msg string) *FirewallError {
	return &FirewallError{
		BaseError: ErrFirewallSetup,
		Backend:   backend,
		Operation: operation,
		Message:   msg,
	}
}

// ProcessError represents process management errors
type ProcessError struct {
	BaseError error
	Command   string
	PID       int
	Message   string
}

func (e *ProcessError) Error() string {
	if e.PID > 0 {
		return fmt.Sprintf("%s: %s (command: %s, pid: %d)", e.BaseError, e.Message, e.Command, e.PID)
	}
	return fmt.Sprintf("%s: %s (command: %s)", e.BaseError, e.Message, e.Command)
}

func (e *ProcessError) Unwrap() error {
	return e.BaseError
}

func (e *ProcessError) Is(target error) bool {
	return errors.Is(e.BaseError, target)
}

// NewProcessError creates a new process error
func NewProcessError(command string, pid int, msg string) *ProcessError {
	return &ProcessError{
		BaseError: ErrProcessManagement,
		Command:   command,
		PID:       pid,
		Message:   msg,
	}
}

// ServiceError represents service errors
type ServiceError struct {
	BaseError  error
	InitSystem string
	Operation  string
	Message    string
}

func (e *ServiceError) Error() string {
	return fmt.Sprintf("%s: %s (init: %s, operation: %s)", e.BaseError, e.Message, e.InitSystem, e.Operation)
}

func (e *ServiceError) Unwrap() error {
	return e.BaseError
}

func (e *ServiceError) Is(target error) bool {
	return errors.Is(e.BaseError, target)
}

// NewServiceError creates a new service error
func NewServiceError(initSystem, operation, msg string) *ServiceError {
	return &ServiceError{
		BaseError:  ErrService,
		InitSystem: initSystem,
		Operation:  operation,
		Message:    msg,
	}
}

// Wrap adds context to an error
func Wrap(err error, context string) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("%s: %w", context, err)
}

// Wrapf adds formatted context to an error
func Wrapf(err error, format string, args ...interface{}) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf(format+": %w", append(args, err)...)
}

// Is checks if an error is of a specific type (compatible with errors.Is)
func Is(err, target error) bool {
	return errors.Is(err, target)
}

// As checks if an error is of a specific type (compatible with errors.As)
func As(err error, target interface{}) bool {
	return errors.As(err, target)
}
