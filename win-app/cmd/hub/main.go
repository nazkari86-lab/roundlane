package main

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"roundlane/windows/core"
	"roundlane/windows/winproc"
)

func main() {
	if len(os.Args) != 4 {
		return
	}
	group, token, temporary := os.Args[1], os.Args[2], os.Args[3]
	root, err := os.Executable()
	if err != nil {
		return
	}
	root = filepath.Dir(root)
	read := func(name string) []byte {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			return nil
		}
		return data
	}
	page, script, starter := read("hub/index.html"), read("hub/app.js"), read("starter.cpp")
	if len(page) == 0 || len(script) == 0 || len(starter) == 0 || len(token) == 0 {
		return
	}
	page, err = core.RenderHub(page, group, starter)
	if err != nil {
		return
	}
	config, _ := json.Marshal(map[string]string{"groupURL": group})
	listener, err := net.Listen("tcp4", "127.0.0.1:18765")
	if err != nil {
		return
	}
	mux := http.NewServeMux()
	serve := func(body []byte, contentType string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			w.Header().Set("Content-Type", contentType)
			w.Header().Set("Cache-Control", "no-store")
			w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'")
			w.Header().Set("X-Content-Type-Options", "nosniff")
			_, _ = w.Write(body)
		}
	}
	mux.HandleFunc("GET /{$}", serve(page, "text/html; charset=utf-8"))
	mux.HandleFunc("GET /app.js", serve(script, "application/javascript; charset=utf-8"))
	mux.HandleFunc("GET /starter.cpp", serve(starter, "text/plain; charset=utf-8"))
	mux.HandleFunc("GET /config.json", serve(config, "application/json; charset=utf-8"))
	mux.HandleFunc("GET /health", serve([]byte(token), "text/plain; charset=utf-8"))
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() { _ = server.Serve(listener) }()
	started := time.Now()
	seen := false
	for {
		time.Sleep(2 * time.Second)
		running, err := winproc.Running(core.RuntimeExecutable)
		if err != nil {
			continue
		}
		if running {
			seen = true
		} else if seen || time.Since(started) >= 45*time.Second {
			_ = server.Close()
			if strings.HasPrefix(filepath.Base(temporary), "Roundlane-") {
				_ = os.RemoveAll(temporary)
			}
			return
		}
	}
}
