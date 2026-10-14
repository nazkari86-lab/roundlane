package core

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"howett.net/plist"
)

func TestGeneratedCodeCanExitProfile(t *testing.T) {
	template, err := os.ReadFile("../../mac-codeforces-cppsh-demo.seb")
	if err != nil {
		t.Fatal(err)
	}
	code, err := GenerateCode()
	if err != nil {
		t.Fatal(err)
	}
	if len(code) != 12 || !ValidCode(code) {
		t.Fatal("generated code cannot be entered")
	}
	profile, err := MakeProfile(template, code)
	if err != nil || !ProfileIsRecoverable(profile, code) {
		t.Fatal("generated code cannot exit SEB")
	}
	if !ValidCode(strings.Repeat("a", 32)) || ValidCode(strings.Repeat("a", 33)) {
		t.Fatal("code length boundary")
	}
}

func TestGroupURL(t *testing.T) {
	for _, input := range []string{
		TestContest,
		"codeforces.com/group/AbC123/contest/42",
	} {
		if _, err := GroupURL(input); err != nil {
			t.Errorf("valid %q: %v", input, err)
		}
	}
	for _, input := range []string{
		"https://codeforces.com.evil.test/group/AbC123",
		"https://evil.test/@codeforces.com/group/AbC123",
		"http://codeforces.com/group/AbC123",
		"https://codeforces.com/problemset",
		"https://codeforces.com/group/%2f",
	} {
		if _, err := GroupURL(input); err == nil {
			t.Errorf("accepted invalid %q", input)
		}
	}
}

func TestProfileExitAndRules(t *testing.T) {
	template, err := os.ReadFile("../../mac-codeforces-cppsh-demo.seb")
	if err != nil {
		t.Fatal(err)
	}
	profile, err := MakeProfile(template, "2468")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(profile, []byte("<?xml")) {
		t.Fatal("Windows SEB XML parser requires the XML prefix")
	}
	if !ProfileIsRecoverable(profile, "2468") {
		t.Fatal("generated profile is not recoverable")
	}
	if ProfileIsRecoverable(profile, "1234") {
		t.Fatal("wrong code accepted")
	}
	var settings map[string]interface{}
	if _, err := plist.Unmarshal(profile, &settings); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"allowFind", "enableZoomPage", "showReloadWarning", "newBrowserWindowShowReloadWarning"} {
		if settings[key] != true {
			t.Fatalf("missing usability setting: %s", key)
		}
	}
	settings["allowQuit"] = false
	tampered, err := plist.Marshal(settings, plist.XMLFormat)
	if err != nil {
		t.Fatal(err)
	}
	if ProfileIsRecoverable(tampered, "2468") {
		t.Fatal("non-quittable profile accepted")
	}
	settings["allowQuit"] = true
	settings["URLFilterRules"] = []interface{}{}
	tampered, err = plist.Marshal(settings, plist.XMLFormat)
	if err != nil {
		t.Fatal(err)
	}
	if ProfileIsRecoverable(tampered, "2468") {
		t.Fatal("profile without allow rules accepted")
	}
}

func TestProfileRequiresProtectionService(t *testing.T) {
	template, err := os.ReadFile("../../mac-codeforces-cppsh-demo.seb")
	if err != nil {
		t.Fatal(err)
	}
	profile, err := MakeProfile(template, "1234")
	if err != nil {
		t.Fatal(err)
	}
	var settings map[string]interface{}
	if _, err := plist.Unmarshal(profile, &settings); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"sebServicePolicy", "sebServiceIgnore"} {
		saved := settings[key]
		if key == "sebServicePolicy" {
			settings[key] = 0
		} else {
			settings[key] = true
		}
		downgraded, err := plist.Marshal(settings, plist.XMLFormat)
		if err != nil {
			t.Fatal(err)
		}
		if ProfileIsRecoverable(downgraded, "1234") {
			t.Fatalf("accepted service downgrade through %s", key)
		}
		settings[key] = saved
	}
}
