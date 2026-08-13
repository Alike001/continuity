package journal

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	decryptTimeout  = 2 * time.Second
	maxDecryptBytes = 1 << 20
)

type NodeDecrypter struct {
	endpoint string
	client   *http.Client
}

type decryptRequest struct {
	EncryptedMessage []byte `json:"encryptedMessage"`
}

type decryptResponse struct {
	DecryptedMessage []byte `json:"decryptedMessage"`
}

func NewNodeDecrypter(signPort int) *NodeDecrypter {
	return &NodeDecrypter{
		endpoint: fmt.Sprintf("http://127.0.0.1:%d/decrypt", signPort),
		client: &http.Client{
			Timeout: decryptTimeout,
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
				return errors.New("redirects are not allowed")
			},
		},
	}
}

func (d *NodeDecrypter) Decrypt(ciphertext []byte) ([]byte, error) {
	if len(ciphertext) == 0 {
		return nil, errors.New("ciphertext is empty")
	}
	body, err := json.Marshal(decryptRequest{EncryptedMessage: ciphertext})
	if err != nil {
		return nil, fmt.Errorf("encoding decrypt request: %w", err)
	}
	request, err := http.NewRequest(http.MethodPost, d.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("building decrypt request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := d.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("calling node decrypt: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("calling node decrypt: unexpected HTTP status %d", response.StatusCode)
	}

	limited := io.LimitReader(response.Body, maxDecryptBytes+1)
	responseBody, err := io.ReadAll(limited)
	if err != nil {
		return nil, fmt.Errorf("reading decrypt response: %w", err)
	}
	if len(responseBody) > maxDecryptBytes {
		return nil, errors.New("reading decrypt response: response too large")
	}
	decoder := json.NewDecoder(bytes.NewReader(responseBody))
	decoder.DisallowUnknownFields()
	var decoded decryptResponse
	if err := decoder.Decode(&decoded); err != nil {
		return nil, fmt.Errorf("decoding decrypt response: %w", err)
	}
	if err := requireEOF(decoder); err != nil {
		return nil, fmt.Errorf("decoding decrypt response: %w", err)
	}
	if len(decoded.DecryptedMessage) == 0 {
		return nil, errors.New("decoding decrypt response: plaintext is empty")
	}
	return decoded.DecryptedMessage, nil
}
