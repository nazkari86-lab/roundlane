package core

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const RuntimeExecutable = "Roundlane.Runtime.exe"

func RuntimePath(root string) string { return filepath.Join(root, "runtime", RuntimeExecutable) }

// VerifyRuntime authenticates the release manifest before checking runtime bytes.
func VerifyRuntime(root string) error {
	return verifyRuntimeWithKey(root, RuntimePublicKey)
}

func verifyRuntimeWithKey(root, publicKeyHex string) error {
	root = filepath.Join(root, "runtime")
	data, err := os.ReadFile(filepath.Join(root, "manifest.json"))
	if err != nil {
		return fmt.Errorf("встроенный режим Roundlane отсутствует: %w", err)
	}
	key, keyErr := hex.DecodeString(publicKeyHex)
	signature, sigErr := os.ReadFile(filepath.Join(root, "manifest.sig"))
	if keyErr != nil || len(key) != ed25519.PublicKeySize || sigErr != nil || !ed25519.Verify(ed25519.PublicKey(key), data, signature) {
		return fmt.Errorf("подпись компонентов Roundlane недействительна; установите проверенную копию")
	}
	data = bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf})
	var manifest struct {
		Version string `json:"version"`
		Files   []struct {
			Path   string `json:"path"`
			SHA256 string `json:"sha256"`
		} `json:"files"`
	}
	if err := json.Unmarshal(data, &manifest); err != nil || manifest.Version != "3.0" {
		return fmt.Errorf("повреждён манифест встроенного режима Roundlane")
	}
	required := map[string]bool{RuntimeExecutable: false, "Roundlane.Client.exe": false, "Roundlane.Service.exe": false, "Roundlane.Recovery.exe": false, "libcef.dll": false, "CefSharp.Core.Runtime.dll": false}
	seen := map[string]bool{}
	for _, file := range manifest.Files {
		name := filepath.FromSlash(file.Path)
		if !filepath.IsLocal(name) || strings.Contains(file.Path, "\\") || seen[strings.ToLower(file.Path)] {
			return fmt.Errorf("недопустимый путь в манифесте Roundlane")
		}
		seen[strings.ToLower(file.Path)] = true
		expected, err := hex.DecodeString(file.SHA256)
		if err != nil || len(expected) != sha256.Size {
			return fmt.Errorf("неверная контрольная сумма %s", file.Path)
		}
		// Reject redirects in every parent, not just the final file.
		parent := root
		for _, part := range strings.Split(filepath.Dir(name), string(filepath.Separator)) {
			if part == "." {
				continue
			}
			parent = filepath.Join(parent, part)
			info, err := os.Lstat(parent)
			if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
				return fmt.Errorf("недопустимый каталог компонента %s", file.Path)
			}
		}
		info, err := os.Lstat(filepath.Join(root, name))
		if err != nil || !info.Mode().IsRegular() {
			return fmt.Errorf("отсутствует компонент %s", file.Path)
		}
		f, err := os.Open(filepath.Join(root, name))
		if err != nil {
			return err
		}
		h := sha256.New()
		_, copyErr := io.Copy(h, f)
		f.Close()
		if copyErr != nil || !bytes.Equal(h.Sum(nil), expected) {
			return fmt.Errorf("повреждён компонент %s", file.Path)
		}
		if _, ok := required[file.Path]; ok {
			required[file.Path] = true
		}
	}
	for name, found := range required {
		if !found {
			return fmt.Errorf("в манифесте отсутствует %s", name)
		}
	}
	err = filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("недопустимая ссылка в компонентах Roundlane")
		}
		if entry.IsDir() {
			return nil
		}
		rel, e := filepath.Rel(root, path)
		if e != nil {
			return e
		}
		rel = filepath.ToSlash(rel)
		if rel != "manifest.json" && rel != "manifest.sig" && !seen[strings.ToLower(rel)] {
			return fmt.Errorf("неизвестный компонент %s", rel)
		}
		return nil
	})
	return err
}
