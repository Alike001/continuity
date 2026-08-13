//go:build continuity_fcc

package main

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
)

func TestRequiredHash(t *testing.T) {
	value := "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	t.Setenv("VALUE", value)
	if got, err := requiredHash("VALUE"); err != nil || got != common.HexToHash(value) {
		t.Fatalf("valid hash rejected: %v", err)
	}
	for _, invalid := range []string{"", "0x01", value[2:]} {
		t.Setenv("VALUE", invalid)
		if _, err := requiredHash("VALUE"); err == nil {
			t.Fatalf("invalid hash accepted: %q", invalid)
		}
	}
}

func TestIntEnv(t *testing.T) {
	for _, invalid := range []string{"", "0", "65536", "bad"} {
		t.Setenv("PORT", invalid)
		if got := intEnv("PORT", 8080); got != 8080 {
			t.Fatalf("invalid port did not use fallback: %q", invalid)
		}
	}
	t.Setenv("PORT", "9090")
	if got := intEnv("PORT", 8080); got != 9090 {
		t.Fatalf("valid port rejected: %d", got)
	}
}
