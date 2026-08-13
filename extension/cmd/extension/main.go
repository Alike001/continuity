package main

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/Alike001/continuity/extension/internal/journal"
	"github.com/ethereum/go-ethereum/common"
)

func main() {
	applicationID, err := requiredHash("APPLICATION_ID")
	if err != nil {
		log.Fatal(err)
	}
	teeID, err := requiredAddress("TEE_ID")
	if err != nil {
		log.Fatal(err)
	}
	extensionPort, err := port("EXTENSION_PORT", 8080)
	if err != nil {
		log.Fatal(err)
	}
	signPort, err := port("SIGN_PORT", 9090)
	if err != nil {
		log.Fatal(err)
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
	log.Printf("continuity extension listening on %s", server.Addr)
	if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func requiredHash(name string) (common.Hash, error) {
	value := os.Getenv(name)
	if len(value) != 2+common.HashLength*2 || value[:2] != "0x" || !common.IsHexHash(value) {
		return common.Hash{}, fmt.Errorf("%s must be a 32-byte 0x hash", name)
	}
	return common.HexToHash(value), nil
}

func requiredAddress(name string) (common.Address, error) {
	value := os.Getenv(name)
	if len(value) != 2+common.AddressLength*2 || value[:2] != "0x" || !common.IsHexAddress(value) {
		return common.Address{}, fmt.Errorf("%s must be a 20-byte 0x address", name)
	}
	address := common.HexToAddress(value)
	if address == (common.Address{}) {
		return common.Address{}, fmt.Errorf("%s must not be zero", name)
	}
	return address, nil
}

func port(name string, fallback int) (int, error) {
	value := os.Getenv(name)
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 1 || parsed > 65535 {
		return 0, fmt.Errorf("%s must be a valid TCP port", name)
	}
	return parsed, nil
}
