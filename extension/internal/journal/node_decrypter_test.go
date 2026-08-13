package journal

import (
	"fmt"
	"net"
	"net/http"
	"testing"
	"time"
)

func testNodeDecrypter(t *testing.T, handler http.Handler) *NodeDecrypter {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: handler}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Close() })
	return NewNodeDecrypter(listener.Addr().(*net.TCPAddr).Port)
}

func TestNodeDecrypter(t *testing.T) {
	decrypter := testNodeDecrypter(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/decrypt" || r.Method != http.MethodPost {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"decryptedMessage":"cGxhaW50ZXh0"}`))
	}))
	plaintext, err := decrypter.Decrypt([]byte{1})
	if err != nil {
		t.Fatal(err)
	}
	if string(plaintext) != "plaintext" {
		t.Fatalf("wrong plaintext %q", plaintext)
	}
}

func TestNodeDecrypterRejectsUnsafeResponses(t *testing.T) {
	tests := []struct {
		name    string
		handler http.Handler
	}{
		{name: "HTTP error", handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { http.Error(w, "no", http.StatusBadGateway) })},
		{name: "redirect", handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, "http://example.com", http.StatusFound)
		})},
		{name: "unknown field", handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"decryptedMessage":"YQ==","extra":true}`))
		})},
		{name: "empty plaintext", handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte(`{"decryptedMessage":""}`)) })},
		{name: "trailing JSON", handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte(`{"decryptedMessage":"YQ=="} {}`)) })},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := testNodeDecrypter(t, test.handler).Decrypt([]byte{1})
			if err == nil {
				t.Fatal("unsafe response accepted")
			}
		})
	}
}

func TestNodeDecrypterRejectsOversizeAndTimeout(t *testing.T) {
	oversized := testNodeDecrypter(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(make([]byte, maxDecryptBytes+1))
	}))
	if _, err := oversized.Decrypt([]byte{1}); err == nil {
		t.Fatal("oversized response accepted")
	}

	slow := testNodeDecrypter(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(20 * time.Millisecond)
		_, _ = fmt.Fprint(w, `{"decryptedMessage":"YQ=="}`)
	}))
	slow.client.Timeout = time.Millisecond
	if _, err := slow.Decrypt([]byte{1}); err == nil {
		t.Fatal("timeout accepted")
	}
}
