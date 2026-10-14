package core

import (
	"errors"
	"os"
	"strings"
	"testing"
)

func signedFixture(t *testing.T) Competition {
	t.Helper()
	b, err := os.ReadFile("testdata/participant.roundlane")
	if err != nil {
		t.Fatal(err)
	}
	c, err := DecodeCompetition(b)
	if err != nil {
		t.Fatal(err)
	}
	return c
}
func TestParticipantSignatureAndTampering(t *testing.T) {
	c := signedFixture(t)
	if !c.IsParticipant() {
		t.Fatal("participant mode missing")
	}
	for _, change := range []func(*Competition){
		func(c *Competition) { c.GroupURL = strings.Replace(c.GroupURL, "723396", "723397", -1) },
		func(c *Competition) { c.QuitPasswordHash = strings.Repeat("0", 64) },
		func(c *Competition) { c.Signature = "" },
		func(c *Competition) { c.Signature = strings.Repeat("0", 128) },
		func(c *Competition) { c.Version = 2 },
	} {
		bad := c
		change(&bad)
		if _, err := bad.Validated(); err == nil {
			t.Fatal("tampered settings accepted")
		}
	}
	b, err := c.Encode()
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), `"code"`) || strings.Contains(string(b), `"password"`) {
		t.Fatal("plaintext field exported")
	}
}
func TestParticipantLaunchRouting(t *testing.T) {
	c := signedFixture(t)
	started, saved := 0, 0
	start := func(c Competition) error {
		started++
		if !c.IsParticipant() {
			t.Fatal("wrong mode")
		}
		return nil
	}
	remember := func(c Competition) error { saved++; return nil }
	if err := LaunchParticipant(c, start, remember); err != nil || started != 1 || saved != 1 {
		t.Fatalf("direct start: %v %d %d", err, started, saved)
	}
	c.Signature = ""
	if err := LaunchParticipant(c, start, remember); err == nil || started != 1 || saved != 1 {
		t.Fatal("tampered config launched")
	}
	old, err := NewCompetition("https://codeforces.com/group/Test123/contest/42", "7484")
	if err != nil {
		t.Fatal(err)
	}
	if err := LaunchParticipant(old, start, remember); err == nil || started != 1 {
		t.Fatal("unsigned config launched directly")
	}
	c = signedFixture(t)
	sentinel := errors.New("runtime unavailable")
	if err := LaunchParticipant(c, func(Competition) error { return sentinel }, remember); !errors.Is(err, sentinel) || saved != 1 {
		t.Fatal("failure persisted settings")
	}
}
