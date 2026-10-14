package core

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiagnosticArgumentErrorsNeverBecomeExamStartup(t *testing.T) {
	for _, args := range [][]string{{"--check-settings"}, {"--settings"}, {"--report", "out.json"}, {"--unknown"}, {"--check-runtime", "--settings", "contest.roundlane"}, {"--check-settings", "a.roundlane", "--organizer-tools"}, {"--settings", "--check-runtime"}, {"--organizer-tools", "--organizer-tools"}} {
		if _, err := ParseLaunchArguments(args); err == nil {
			t.Errorf("accepted malformed invocation %v", args)
		}
	}
	for _, args := range [][]string{nil, {"contest.roundlane"}, {"--organizer-tools"}, {"--check-runtime", "--report", "report.json"}, {"--check-settings", "contest.roundlane"}, {"--settings", "contest.roundlane", "--organizer-tools"}} {
		if _, err := ParseLaunchArguments(args); err != nil {
			t.Errorf("rejected valid invocation %v: %v", args, err)
		}
	}
}

func TestNewBundleOverridesOldSavedContest(t *testing.T) {
	root := t.TempDir()
	bundle := filepath.Join(root, "competition.roundlane")
	saved := filepath.Join(root, "participant.roundlane")
	for _, p := range []string{bundle, saved} {
		if err := os.WriteFile(p, []byte("fixture"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	path, err := DefaultSettingsPath(bundle, saved)
	if err != nil || path != bundle {
		t.Fatal("stale saved settings took precedence")
	}
	if err := os.Remove(bundle); err != nil {
		t.Fatal(err)
	}
	path, err = DefaultSettingsPath(bundle, saved)
	if err != nil || path != saved {
		t.Fatal("legacy saved fallback lost")
	}
	if _, err = DefaultSettingsPath(root, saved); err == nil {
		t.Fatal("invalid bundle silently fell back")
	}
}

func TestParticipantCannotChooseOwnExitCodeThroughOrganizerMode(t *testing.T) {
	bundle := Competition{Format: "roundlane-participant"}
	unsigned := Competition{Format: "roundlane-competition"}
	if !RequiresOrganizerAuthorization(bundle, bundle, true) || !RequiresOrganizerAuthorization(bundle, unsigned, false) {
		t.Fatal("organizer authorization bypass")
	}
	if RequiresOrganizerAuthorization(bundle, bundle, false) || RequiresOrganizerAuthorization(unsigned, unsigned, true) {
		t.Fatal("normal participant or legacy standalone startup blocked")
	}
}

func TestOrganizerCodeValidation(t *testing.T) {
	hash := PasswordHash("ExamplePass123456")
	if !VerifyOrganizerCode("ExamplePass123456", hash) || VerifyOrganizerCode("1234", hash) || VerifyOrganizerCode("ExamplePass123456", "bad") {
		t.Fatal("organizer code validation")
	}
}
