package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

func startHub(group, temporary string) (*exec.Cmd, error) {
	tokenBytes := make([]byte, 16)
	if _, err := rand.Read(tokenBytes); err != nil {
		_ = os.RemoveAll(temporary)
		return nil, err
	}
	token := hex.EncodeToString(tokenBytes)
	helper := exec.Command(filepath.Join(installDir(), "RoundlaneHub.exe"), group, token, temporary)
	helper.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := helper.Start(); err != nil {
		_ = os.RemoveAll(temporary)
		return nil, fmt.Errorf("не удалось запустить стартовую страницу: %w", err)
	}
	client := &http.Client{Timeout: 500 * time.Millisecond}
	healthy := false
	for i := 0; i < 15; i++ {
		resp, err := client.Get("http://127.0.0.1:18765/health")
		if err == nil {
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 100))
			_ = resp.Body.Close()
			if resp.StatusCode == 200 && string(body) == token {
				healthy = true
				break
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	if !healthy {
		_ = helper.Process.Kill()
		_ = os.RemoveAll(temporary)
		return nil, errors.New("стартовая страница не открылась; возможно, порт 18765 занят")
	}
	return helper, nil
}
