package main

import (
	"github.com/lxn/walk"
	"os"
	"path/filepath"
	"roundlane/windows/core"
)

func participantPath() string {
	base, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(base, "Roundlane", "participant.roundlane")
}
func rememberParticipant(c core.Competition) error {
	path := participantPath()
	if path == "" {
		return os.ErrNotExist
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	return saveCompetition(path, c)
}
func runParticipant(c core.Competition) {
	// The shared settings contain only a hash; never load or save organizer secrets.
	err := core.LaunchParticipant(c, func(checked core.Competition) error {
		if err := readiness(); err != nil {
			return err
		}
		return startContest(checked.GroupURL, checked.QuitPasswordHash)
	}, func(checked core.Competition) error {
		// A failed settings copy must not terminate an already protected runtime.
		_ = rememberParticipant(checked)
		return nil
	})
	if err != nil {
		walk.MsgBox(nil, "Не удалось открыть соревнование", err.Error(), walk.MsgBoxOK|walk.MsgBoxIconError)
	}
}
