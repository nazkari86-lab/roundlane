// Organizer-only tool. Never packages the private signing seed or exit code.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"roundlane/windows/core"
)

func main() {
	keyPath := flag.String("key", "", "private organizer signing seed")
	group := flag.String("group", "", "exact contest URL")
	settings := flag.String("settings", "", "participant output file")
	private := flag.String("organizer", "", "private organizer instructions output")
	flag.Parse()
	if *keyPath == "" || *settings == "" || *private == "" || *group == "" {
		fail(fmt.Errorf("key, group, settings and organizer paths are required"))
	}
	if filepath.Clean(*settings) == filepath.Clean(*private) {
		fail(fmt.Errorf("participant and organizer files must differ"))
	}
	seed, err := os.ReadFile(*keyPath)
	if err != nil {
		fail(err)
	}
	if len(seed) != ed25519.SeedSize {
		fail(fmt.Errorf("invalid signing seed"))
	}
	// Uniform selection without modulo bias; omit visually confusing characters.
	alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
	code := make([]byte, 16)
	for i := range code {
		for {
			var b [1]byte
			if _, err = rand.Read(b[:]); err != nil {
				fail(err)
			}
			if int(b[0]) < 256-256%len(alphabet) {
				code[i] = alphabet[int(b[0])%len(alphabet)]
				break
			}
		}
	}
	c, err := core.NewParticipant(*group, string(code), ed25519.NewKeyFromSeed(seed))
	if err != nil {
		fail(err)
	}
	data, err := c.Encode()
	if err != nil {
		fail(err)
	}
	// Write the recovery information before distributing any participant file.
	instructions := []byte("Roundlane — только организатору. НЕ ПЕРЕДАВАТЬ УЧАСТНИКАМ.\n\nСоревнование: " + c.GroupURL + "\nОбщий код выхода: " + string(code) + "\n\nMac: Cmd+Q → введите код. Windows: Ctrl+Q → введите код.\nДо старта сохраните эту инструкцию отдельно от компьютеров участников.\nУчастникам передаётся только файл competition.roundlane.\nАвтоматический запуск после перезагрузки ОС не устанавливается.\n")
	if err = writeNew(*private, instructions, 0600); err != nil {
		fail(err)
	}
	if err = writeNew(*settings, data, 0644); err != nil {
		fail(err)
	}
	fmt.Println("Signed participant file and private organizer instructions created; code was not printed.")
}
func writeNew(path string, data []byte, mode os.FileMode) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	e := f.Close()
	if err == nil {
		err = e
	}
	return err
}
func fail(err error) { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
