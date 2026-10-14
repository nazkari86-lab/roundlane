package core

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestRuntimeCorruptionAndMissingPayload(t *testing.T) {
	root := t.TempDir()
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	check := func() error { return verifyRuntimeWithKey(root, hex.EncodeToString(public)) }
	if check() == nil {
		t.Fatal("accepted missing native runtime")
	}
	runtime := filepath.Join(root, "runtime")
	os.Mkdir(runtime, 0700)
	files := []map[string]string{}
	for _, name := range []string{RuntimeExecutable, "Roundlane.Client.exe", "Roundlane.Service.exe", "Roundlane.Recovery.exe", "libcef.dll", "CefSharp.Core.Runtime.dll"} {
		data := []byte(name)
		if err := os.WriteFile(filepath.Join(runtime, name), data, 0600); err != nil {
			t.Fatal(err)
		}
		hash := sha256.Sum256(data)
		files = append(files, map[string]string{"path": name, "sha256": hex.EncodeToString(hash[:])})
	}
	manifest, _ := json.Marshal(map[string]interface{}{"version": "3.0", "files": files})
	if err := os.WriteFile(filepath.Join(runtime, "manifest.json"), append([]byte{0xef, 0xbb, 0xbf}, manifest...), 0600); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Join(runtime, "manifest.json"))
	os.WriteFile(filepath.Join(runtime, "manifest.sig"), ed25519.Sign(private, raw), 0600)
	if err := check(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(runtime, RuntimeExecutable), []byte("changed"), 0600); err != nil {
		t.Fatal(err)
	}
	if check() == nil {
		t.Fatal("accepted changed exam executable")
	}
	// An attacker can recompute hashes, but cannot authenticate the changed manifest.
	changedHash := sha256.Sum256([]byte("changed"))
	files[0]["sha256"] = hex.EncodeToString(changedHash[:])
	manifest, _ = json.Marshal(map[string]interface{}{"version": "3.0", "files": files})
	os.WriteFile(filepath.Join(runtime, "manifest.json"), manifest, 0600)
	if check() == nil {
		t.Fatal("accepted replaced executable plus recomputed manifest")
	}
	os.WriteFile(filepath.Join(runtime, "manifest.sig"), ed25519.Sign(private, manifest), 0600)
	if err := check(); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(runtime, "injected.dll"), []byte("unexpected"), 0600)
	if check() == nil {
		t.Fatal("accepted unlisted injected DLL")
	}
	os.Remove(filepath.Join(runtime, "injected.dll"))
	_, otherKey, _ := ed25519.GenerateKey(rand.Reader)
	os.WriteFile(filepath.Join(runtime, "manifest.sig"), ed25519.Sign(otherKey, manifest), 0600)
	if check() == nil {
		t.Fatal("accepted foreign signing key")
	}
	os.Remove(filepath.Join(runtime, "manifest.sig"))
	if check() == nil {
		t.Fatal("accepted absent signature")
	}
	files[0]["path"] = "../foreign.exe"
	manifest, _ = json.Marshal(map[string]interface{}{"version": "3.0", "files": files})
	os.WriteFile(filepath.Join(runtime, "manifest.json"), manifest, 0600)
	os.WriteFile(filepath.Join(runtime, "manifest.sig"), ed25519.Sign(private, manifest), 0600)
	if check() == nil {
		t.Fatal("accepted path outside runtime")
	}
}
