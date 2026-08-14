package internal

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ethereum/go-ethereum/crypto"
)

func TestSnapshotStoreVerifiesKeccakAndIsIdempotent(t *testing.T) {
	store := newTestStore(t)
	ciphertext := []byte("opaque encrypted snapshot")
	digest := "0x" + commonHex(crypto.Keccak256(ciphertext))
	if err := store.Put(digest, ciphertext); err != nil {
		t.Fatalf("put: %v", err)
	}
	if err := store.Put(digest, ciphertext); err != nil {
		t.Fatalf("idempotent put: %v", err)
	}
	if got, err := store.Get(digest); err != nil || !bytes.Equal(got, ciphertext) {
		t.Fatalf("get = %q, %v", got, err)
	}
	if err := store.Put(digest, []byte("substituted")); !errors.Is(err, ErrDigestMismatch) {
		t.Fatalf("substitution error = %v", err)
	}
}

func TestSnapshotStoreRejectsInvalidAndOversizedPayloads(t *testing.T) {
	store := newTestStore(t)
	if err := store.Put("../../escape", []byte("x")); !errors.Is(err, ErrInvalidDigest) {
		t.Fatalf("invalid digest error = %v", err)
	}
	if err := store.Put("0x"+stringsRepeat("0", 64), bytes.Repeat([]byte("x"), MaxSnapshotBytes+1)); !errors.Is(err, ErrSnapshotTooLarge) {
		t.Fatalf("oversize error = %v", err)
	}
}

func TestSnapshotStoreHTTPPutAndGet(t *testing.T) {
	store := newTestStore(t)
	ciphertext := []byte("http ciphertext")
	digest := "0x" + commonHex(crypto.Keccak256(ciphertext))
	server := httptest.NewServer(store.Handler())
	t.Cleanup(server.Close)
	request, _ := http.NewRequest(http.MethodPut, server.URL+"/snapshots/"+digest, bytes.NewReader(ciphertext))
	response, err := http.DefaultClient.Do(request)
	if err != nil || response.StatusCode != http.StatusCreated {
		t.Fatalf("put status = %v, %v", response.StatusCode, err)
	}
	response.Body.Close()
	response, err = http.Get(server.URL + "/snapshots/" + digest)
	if err != nil || response.StatusCode != http.StatusOK {
		t.Fatalf("get status = %v, %v", response.StatusCode, err)
	}
	body, _ := io.ReadAll(response.Body)
	response.Body.Close()
	if !bytes.Equal(body, ciphertext) {
		t.Fatalf("get body = %q", body)
	}
}

func newTestStore(t *testing.T) *SnapshotStore {
	t.Helper()
	root := t.TempDir()
	store, err := NewSnapshotStore(root)
	if err != nil {
		t.Fatal(err)
	}
	return store
}

func commonHex(value []byte) string {
	const hexChars = "0123456789abcdef"
	result := make([]byte, len(value)*2)
	for index, item := range value {
		result[index*2] = hexChars[item>>4]
		result[index*2+1] = hexChars[item&15]
	}
	return string(result)
}

func stringsRepeat(value string, count int) string {
	result := ""
	for index := 0; index < count; index++ {
		result += value
	}
	return result
}
