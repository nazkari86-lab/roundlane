package core

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"howett.net/plist"
)

func TestSharedCompetitionRoundTrip(t *testing.T) {
	c, err := NewCompetition("codeforces.com/group/Test123/contest/42", "7484")
	if err != nil {
		t.Fatal(err)
	}
	data, err := c.Encode()
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(data, []byte(`"code"`)) || bytes.Contains(data, []byte(`"7484"`)) {
		t.Fatal("plaintext code exported")
	}
	loaded, err := DecodeCompetition(data)
	if err != nil || loaded != c {
		t.Fatalf("round-trip: %+v %v", loaded, err)
	}
	fixture, err := os.ReadFile("testdata/competition.roundlane")
	if err != nil {
		t.Fatal(err)
	}
	shared, err := DecodeCompetition(fixture)
	if err != nil || shared != c {
		t.Fatalf("shared fixture mismatch: %+v %v", shared, err)
	}
	template, err := os.ReadFile("../../mac-codeforces-cppsh-demo.seb")
	if err != nil {
		t.Fatal(err)
	}
	profile, err := MakeProfileWithHash(template, shared.QuitPasswordHash)
	if err != nil {
		t.Fatal(err)
	}
	if !ProfileIsRecoverable(profile, "7484") || ProfileIsRecoverable(profile, "1234") {
		t.Fatal("import changed quit code")
	}
	var settings map[string]interface{}
	if _, err := plist.Unmarshal(profile, &settings); err != nil {
		t.Fatal(err)
	}
	if settings["hashedQuitPassword"] != PasswordHash("7484") {
		t.Fatal("wrong SEB quit hash")
	}
}

func TestCompetitionRejectsInvalidInput(t *testing.T) {
	valid, err := NewCompetition("https://codeforces.com/group/Test123/contest/42", "7484")
	if err != nil {
		t.Fatal(err)
	}
	good, err := valid.Encode()
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string][]byte{
		"empty":          nil,
		"null":           []byte("null"),
		"array":          []byte("[]"),
		"version":        bytes.Replace(good, []byte(`"version": 1`), []byte(`"version": 2`), 1),
		"bool version":   bytes.Replace(good, []byte(`"version": 1`), []byte(`"version": true`), 1),
		"float version":  bytes.Replace(good, []byte(`"version": 1`), []byte(`"version": 1.0`), 1),
		"external group": bytes.Replace(good, []byte("codeforces.com/group"), []byte("codeforces.com.evil.test/group"), 1),
		"hash":           bytes.Replace(good, []byte(valid.QuitPasswordHash), []byte("7484"), 1),
		"missing hash":   []byte(`{"format":"roundlane-competition","version":1,"groupURL":"https://codeforces.com/group/Test123/contest/42"}`),
		"unknown field":  bytes.Replace(good, []byte(`"version": 1`), []byte(`"version": 1, "code": "7484"`), 1),
		"trailing json":  append(append([]byte{}, good...), []byte("{}")...),
		"oversize":       []byte(strings.Repeat(" ", MaxCompetitionBytes+1)),
	}
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := DecodeCompetition(data); err == nil {
				t.Fatal("invalid settings accepted")
			}
		})
	}
	if _, err := MakeProfileWithHash([]byte("not plist"), PasswordHash("7484")); err == nil {
		t.Fatal("invalid template accepted")
	}
	if _, err := MakeProfileWithHash(nil, "7484"); err == nil {
		t.Fatal("plaintext accepted as hash")
	}
}
