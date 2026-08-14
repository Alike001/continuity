package internal

import (
	"bytes"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/ethereum/go-ethereum/crypto"
)

const MaxSnapshotBytes = 256 * 1024

var digestPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)

var (
	ErrInvalidDigest    = errors.New("snapshot digest must be a 32-byte 0x-prefixed hex value")
	ErrDigestMismatch   = errors.New("snapshot bytes do not match the requested digest")
	ErrSnapshotConflict = errors.New("snapshot digest already contains different bytes")
	ErrSnapshotTooLarge = errors.New("snapshot exceeds the 256 KiB limit")
)

// SnapshotStore keeps opaque FCC ciphertext content-addressed by its Ethereum Keccak digest.
// It never decrypts, signs, or interprets the payload.
type SnapshotStore struct{ root string }

func NewSnapshotStore(root string) (*SnapshotStore, error) {
	if strings.TrimSpace(root) == "" {
		return nil, errors.New("snapshot store root is required")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, fmt.Errorf("create snapshot store: %w", err)
	}
	return &SnapshotStore{root: root}, nil
}

func normalizeDigest(digest string) (string, error) {
	if !digestPattern.MatchString(digest) {
		return "", ErrInvalidDigest
	}
	return strings.ToLower(digest), nil
}

func (s *SnapshotStore) path(digest string) (string, error) {
	normalized, err := normalizeDigest(digest)
	if err != nil {
		return "", err
	}
	return filepath.Join(s.root, normalized[2:]), nil
}

func (s *SnapshotStore) Put(digest string, ciphertext []byte) error {
	path, err := s.path(digest)
	if err != nil {
		return err
	}
	if len(ciphertext) == 0 {
		return errors.New("snapshot ciphertext must not be empty")
	}
	if len(ciphertext) > MaxSnapshotBytes {
		return ErrSnapshotTooLarge
	}
	decoded, err := hex.DecodeString(path[len(s.root)+1:])
	if err != nil || !bytes.Equal(crypto.Keccak256(ciphertext), decoded) {
		return ErrDigestMismatch
	}
	if existing, readErr := os.ReadFile(path); readErr == nil {
		if bytes.Equal(existing, ciphertext) {
			return nil
		}
		return ErrSnapshotConflict
	} else if !errors.Is(readErr, os.ErrNotExist) {
		return fmt.Errorf("read existing snapshot: %w", readErr)
	}
	tmp, err := os.CreateTemp(s.root, ".snapshot-*")
	if err != nil {
		return fmt.Errorf("create snapshot temp: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("protect snapshot temp: %w", err)
	}
	if _, err := tmp.Write(ciphertext); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("write snapshot: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("sync snapshot: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close snapshot: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		if existing, readErr := os.ReadFile(path); readErr == nil && bytes.Equal(existing, ciphertext) {
			return nil
		}
		return fmt.Errorf("commit snapshot: %w", err)
	}
	return nil
}

func (s *SnapshotStore) Get(digest string) ([]byte, error) {
	path, err := s.path(digest)
	if err != nil {
		return nil, err
	}
	return os.ReadFile(path)
}

// Handler serves local operator storage. PUT verifies and stores opaque ciphertext. GET returns it.
func (s *SnapshotStore) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/snapshots/") {
			http.NotFound(w, r)
			return
		}
		digest := strings.TrimPrefix(r.URL.Path, "/snapshots/")
		switch r.Method {
		case http.MethodPut:
			body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxSnapshotBytes+1))
			if err != nil {
				http.Error(w, err.Error(), http.StatusRequestEntityTooLarge)
				return
			}
			if err := s.Put(digest, body); err != nil {
				status := http.StatusBadRequest
				if errors.Is(err, ErrSnapshotTooLarge) {
					status = http.StatusRequestEntityTooLarge
				} else if errors.Is(err, ErrSnapshotConflict) {
					status = http.StatusConflict
				}
				http.Error(w, err.Error(), status)
				return
			}
			w.WriteHeader(http.StatusCreated)
		case http.MethodGet:
			body, err := s.Get(digest)
			if errors.Is(err, os.ErrNotExist) {
				http.NotFound(w, r)
				return
			}
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			w.Header().Set("content-type", "application/octet-stream")
			_, _ = w.Write(body)
		default:
			w.Header().Set("allow", "GET, PUT")
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	})
}
