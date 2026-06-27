package api

import (
	"testing"
	"time"
)

func TestFormatTimeUsesBeijingTime(t *testing.T) {
	value := time.Date(2026, 6, 27, 14, 35, 53, 0, time.UTC)

	if got := formatTime(value); got != "2026-06-27 22:35:53" {
		t.Fatalf("formatTime() = %q, want Beijing time", got)
	}
	if got := formatTimeISO(value); got != "2026-06-27T14:35:53Z" {
		t.Fatalf("formatTimeISO() = %q, want UTC RFC3339", got)
	}
}
