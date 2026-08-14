package main

import (
	"crypto/ecdsa"
	"encoding/hex"
	"flag"
	"fmt"
	"math/big"
	"os"
	"strings"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	teeutils "github.com/flare-foundation/tee-node/pkg/utils"
)

func main() {
	var x, y, plaintext string
	flag.StringVar(&x, "x", "", "32-byte public-key x coordinate")
	flag.StringVar(&y, "y", "", "32-byte public-key y coordinate")
	flag.StringVar(&plaintext, "plaintext", "", "plaintext entry to encrypt")
	flag.Parse()
	if plaintext == "" || !common.IsHexHash(x) || !common.IsHexHash(y) {
		fmt.Fprintln(os.Stderr, "usage: acceptance-crypto -x 0x... -y 0x... -plaintext entry")
		os.Exit(2)
	}
	publicKey := &ecdsa.PublicKey{Curve: crypto.S256(), X: new(big.Int).SetBytes(mustHex(x)), Y: new(big.Int).SetBytes(mustHex(y))}
	ciphertext, err := teeutils.Encrypt([]byte(plaintext), publicKey)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("0x%s\n", hex.EncodeToString(ciphertext))
}

func mustHex(value string) []byte {
	decoded, err := hex.DecodeString(strings.TrimPrefix(value, "0x"))
	if err != nil {
		panic(err)
	}
	return decoded
}
