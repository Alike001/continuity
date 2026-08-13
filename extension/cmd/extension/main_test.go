package main

import (
	"testing"

	"github.com/ethereum/go-ethereum/common"
)

func TestRequiredHash(t *testing.T) {
	t.Setenv("VALUE", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	if got, err := requiredHash("VALUE"); err != nil || got != common.HexToHash("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") {
		t.Fatalf("valid hash rejected: %v", err)
	}
	for _, value := range []string{"", "0x01", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"} {
		t.Setenv("VALUE", value)
		if _, err := requiredHash("VALUE"); err == nil {
			t.Fatalf("invalid hash accepted: %q", value)
		}
	}
}

func TestRequiredAddress(t *testing.T) {
	valid := "0x1111111111111111111111111111111111111111"
	t.Setenv("VALUE", valid)
	if got, err := requiredAddress("VALUE"); err != nil || got != common.HexToAddress(valid) {
		t.Fatalf("valid address rejected: %v", err)
	}
	for _, value := range []string{"", "0x1", "1111111111111111111111111111111111111111", "0x0000000000000000000000000000000000000000"} {
		t.Setenv("VALUE", value)
		if _, err := requiredAddress("VALUE"); err == nil {
			t.Fatalf("invalid address accepted: %q", value)
		}
	}
}

func TestPort(t *testing.T) {
	t.Setenv("PORT", "")
	if got, err := port("PORT", 8080); err != nil || got != 8080 {
		t.Fatalf("fallback port rejected: %d %v", got, err)
	}
	for _, value := range []string{"0", "65536", "abc"} {
		t.Setenv("PORT", value)
		if _, err := port("PORT", 8080); err == nil {
			t.Fatalf("invalid port accepted: %q", value)
		}
	}
	t.Setenv("PORT", "9090")
	if got, err := port("PORT", 8080); err != nil || got != 9090 {
		t.Fatalf("valid port rejected: %d %v", got, err)
	}
}
