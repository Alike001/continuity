//go:build continuity_fcc

package main

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/Alike001/continuity/extension/internal/journal"
	"github.com/ethereum/go-ethereum/common"
	teeServer "github.com/flare-foundation/tee-node/pkg/server"
)

func main() {
	applicationID, err := requiredHash("APPLICATION_ID")
	if err != nil {
		log.Fatal(err)
	}
	configPort := intEnv("CONFIG_PORT", 5501)
	signPort := intEnv("SIGN_PORT", 7701)
	extensionPort := intEnv("EXTENSION_PORT", 7702)

	teeID, err := teeServer.StartServerExtensionWithTeeID(configPort, signPort, extensionPort)
	if err != nil {
		log.Fatalf("starting tee-node: %v", err)
	}

	extension := journal.New(applicationID, teeID, journal.NewNodeDecrypter(signPort))
	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", extensionPort),
		Handler:           extension.Handler(),
		ReadHeaderTimeout: 3 * time.Second,
		ReadTimeout:       5 * time.Second,
		WriteTimeout:      5 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("continuity FCC extension listening on %s as %s", server.Addr, teeID.Hex())
		serverErrors <- server.ListenAndServe()
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	select {
	case <-signals:
		if err := server.Close(); err != nil {
			log.Printf("closing extension server: %v", err)
		}
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}
}

func requiredHash(name string) (common.Hash, error) {
	value := os.Getenv(name)
	if len(value) != 2+common.HashLength*2 || value[:2] != "0x" || !common.IsHexHash(value) {
		return common.Hash{}, fmt.Errorf("%s must be a 32-byte 0x hash", name)
	}
	return common.HexToHash(value), nil
}

func intEnv(name string, fallback int) int {
	value, err := strconv.Atoi(os.Getenv(name))
	if err != nil || value < 1 || value > 65535 {
		return fallback
	}
	return value
}
