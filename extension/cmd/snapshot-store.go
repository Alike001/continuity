package main

import (
	"log"
	"net/http"
	"os"

	"github.com/Alike001/continuity/extension/internal"
)

func main() {
	root := os.Getenv("CONTINUITY_SNAPSHOT_DIR")
	if root == "" {
		root = ".fcc-work/snapshots"
	}
	store, err := internal.NewSnapshotStore(root)
	if err != nil {
		log.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(writer http.ResponseWriter, _ *http.Request) {
		writer.Header().Set("content-type", "application/json")
		_, _ = writer.Write([]byte(`{"ok":true,"encryptedPayloadsOnly":true}`))
	})
	mux.Handle("/snapshots/", store.Handler())
	port := os.Getenv("CONTINUITY_SNAPSHOT_PORT")
	if port == "" {
		port = "8790"
	}
	log.Printf("Continuity snapshot store listening on 127.0.0.1:%s", port)
	log.Printf("Opaque ciphertext root: %s", root)
	log.Fatal(http.ListenAndServe("127.0.0.1:"+port, mux))
}
