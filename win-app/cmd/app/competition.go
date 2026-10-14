package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"roundlane/windows/core"
)

func loadCompetition(path string) (core.Competition, error) {
	f, err := os.Open(path)
	if err != nil {
		return core.Competition{}, fmt.Errorf("не удалось открыть файл настроек: %w", err)
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, core.MaxCompetitionBytes+1))
	if err != nil {
		return core.Competition{}, fmt.Errorf("не удалось прочитать файл настроек: %w", err)
	}
	return core.DecodeCompetition(data)
}

func saveCompetition(path string, c core.Competition) error {
	data, err := c.Encode()
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".roundlane-settings-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	_, err = f.Write(data)
	closeError := f.Close()
	if err != nil {
		return err
	}
	if closeError != nil {
		return closeError
	}
	return os.Rename(f.Name(), path)
}

// Runs the production decoder/profile path without opening SEB or a GUI.
func checkCompetition(path, reportPath string) int {
	c, err := loadCompetition(path)
	if err == nil {
		var template []byte
		template, err = os.ReadFile(filepath.Join(installDir(), "contest.seb"))
		if err == nil {
			_, err = core.MakeProfileWithHash(template, c.QuitPasswordHash, c.GroupURL)
		}
	}
	report := map[string]interface{}{"exam_started": false, "settings_check": "passed", "profile_hash_matches": err == nil}
	if err != nil {
		report["settings_check"] = "failed"
		report["error"] = err.Error()
	} else {
		report["groupURL"] = c.GroupURL
		report["participant_direct_start"] = c.IsParticipant()
		report["signature_verified"] = c.IsParticipant()
	}
	data, _ := json.MarshalIndent(report, "", "  ")
	if reportPath != "" {
		if writeError := os.WriteFile(reportPath, append(data, '\n'), 0600); writeError != nil {
			return 1
		}
	} else {
		fmt.Println(string(data))
	}
	if err != nil {
		return 1
	}
	return 0
}

func checkRuntime(reportPath string) int {
	err := readiness()
	report := map[string]interface{}{"exam_started": false, "external_seb_required": false, "runtime_check": "passed"}
	if err != nil {
		report["runtime_check"] = "failed"
		report["error"] = err.Error()
	}
	data, _ := json.MarshalIndent(report, "", "  ")
	if reportPath != "" {
		if os.WriteFile(reportPath, append(data, '\n'), 0600) != nil {
			return 1
		}
	} else {
		fmt.Println(string(data))
	}
	if err != nil {
		return 1
	}
	return 0
}
