package secretstore

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestProtectedCode(t *testing.T) {
	p := filepath.Join(t.TempDir(), "code.dpapi")
	if _, e := LoadAt(p); !errors.Is(e, os.ErrNotExist) {
		t.Fatal("missing record")
	}
	if e := SaveAt(p, "7391"); e != nil {
		t.Fatal(e)
	}
	b, e := os.ReadFile(p)
	if e != nil || bytes.Contains(b, []byte("7391")) {
		t.Fatal("plaintext stored")
	}
	code, e := LoadAt(p)
	if e != nil || code != "7391" {
		t.Fatal("restore")
	}
	if e = SaveAt(p, "7392"); e != nil {
		t.Fatal(e)
	}
	code, e = LoadAt(p)
	if e != nil || code != "7392" {
		t.Fatal("replace")
	}
	if e = SaveAt(p, "x"); e == nil {
		t.Fatal("invalid accepted")
	}
	code, _ = LoadAt(p)
	if code != "7392" {
		t.Fatal("invalid overwrote record")
	}
	if e = os.WriteFile(p, []byte("broken"), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e = LoadAt(p); e == nil {
		t.Fatal("corruption accepted")
	}
}
