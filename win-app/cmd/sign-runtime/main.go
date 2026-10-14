// Roundlane release signing. The private key must never enter participant packages.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
)

func main() {
	if len(os.Args) != 3 {
		panic("usage: sign-runtime PRIVATE_KEY RUNTIME_DIRECTORY")
	}
	keyPath, root := os.Args[1], os.Args[2]
	seed, err := os.ReadFile(keyPath)
	if os.IsNotExist(err) {
		if err = os.MkdirAll(filepath.Dir(keyPath), 0700); err != nil {
			panic(err)
		}
		seed = make([]byte, ed25519.SeedSize)
		if _, err = rand.Read(seed); err != nil {
			panic(err)
		}
		f, e := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if e != nil {
			panic(e)
		}
		_, e = f.Write(seed)
		closeErr := f.Close()
		if e != nil {
			panic(e)
		}
		if closeErr != nil {
			panic(closeErr)
		}
	} else if err != nil {
		panic(err)
	}
	if len(seed) != ed25519.SeedSize {
		panic("invalid release signing seed")
	}
	key := ed25519.NewKeyFromSeed(seed)
	data, err := os.ReadFile(filepath.Join(root, "manifest.json"))
	if err != nil {
		panic(err)
	}
	if err = os.WriteFile(filepath.Join(root, "manifest.sig"), ed25519.Sign(key, data), 0644); err != nil {
		panic(err)
	}
	fmt.Print(hex.EncodeToString(key.Public().(ed25519.PublicKey)))
}
