// Protected organizer code, scoped to the current Windows user.
package secretstore

import (
	"errors"
	"golang.org/x/sys/windows"
	"os"
	"path/filepath"
	"roundlane/windows/core"
	"runtime"
	"unsafe"
)

var ErrInvalid = errors.New("сохранённый код повреждён")

func Path() (string, error) {
	base, err := os.UserConfigDir()
	return filepath.Join(base, "Roundlane", "organizer-code.dpapi"), err
}
func Save(code string) error {
	path, err := Path()
	if err != nil {
		return err
	}
	return SaveAt(path, code)
}
func Load() (string, error) {
	path, err := Path()
	if err != nil {
		return "", err
	}
	return LoadAt(path)
}
func protect(data []byte, decrypt bool) ([]byte, error) {
	if len(data) == 0 || len(data) > 65536 {
		return nil, ErrInvalid
	}
	in := windows.DataBlob{Size: uint32(len(data)), Data: &data[0]}
	var out windows.DataBlob
	var err error
	if decrypt {
		err = windows.CryptUnprotectData(&in, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out)
	} else {
		err = windows.CryptProtectData(&in, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out)
	}
	runtime.KeepAlive(data)
	if err != nil {
		return nil, err
	}
	if out.Data != nil {
		defer windows.LocalFree(windows.Handle(uintptr(unsafe.Pointer(out.Data))))
	}
	if out.Data == nil || out.Size == 0 || out.Size > 65536 {
		return nil, ErrInvalid
	}
	return append([]byte(nil), unsafe.Slice(out.Data, int(out.Size))...), nil
}
func SaveAt(path, code string) error {
	if !core.ValidCode(code) {
		return ErrInvalid
	}
	data, err := protect([]byte(code), false)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), "organizer-code-*.tmp")
	if err != nil {
		return err
	}
	pending := f.Name()
	defer os.Remove(pending)
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	closed := f.Close()
	if err == nil {
		err = closed
	}
	if err != nil {
		return err
	}
	return os.Rename(pending, path)
}
func LoadAt(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil {
		return "", err
	}
	if stat.Size() > 65536 || stat.Size() == 0 {
		return "", ErrInvalid
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	plain, err := protect(data, true)
	if err != nil {
		return "", err
	}
	code := string(plain)
	if !core.ValidCode(code) {
		return "", ErrInvalid
	}
	return code, nil
}
