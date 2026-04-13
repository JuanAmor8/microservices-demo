package main

import (
	"os"
	"testing"
)

func TestGetEnv_ReturnsFallbackWhenNotSet(t *testing.T) {
	os.Unsetenv("TEST_VAR_UNSET")
	result := getEnv("TEST_VAR_UNSET", "fallback")
	if result != "fallback" {
		t.Errorf("expected 'fallback', got '%s'", result)
	}
}

func TestGetEnv_ReturnsValueWhenSet(t *testing.T) {
	os.Setenv("TEST_VAR_SET", "custom")
	defer os.Unsetenv("TEST_VAR_SET")
	result := getEnv("TEST_VAR_SET", "fallback")
	if result != "custom" {
		t.Errorf("expected 'custom', got '%s'", result)
	}
}

func TestGetEnv_ReturnsFallbackWhenEmpty(t *testing.T) {
	os.Setenv("TEST_VAR_EMPTY", "")
	defer os.Unsetenv("TEST_VAR_EMPTY")
	result := getEnv("TEST_VAR_EMPTY", "fallback")
	if result != "fallback" {
		t.Errorf("expected 'fallback' for empty string, got '%s'", result)
	}
}
