package core

import (
	"regexp"
	"testing"
)

func TestOnlySelectedContest(t *testing.T) {
	rules, err := AllowedForContest(TestContest)
	if err != nil {
		t.Fatal(err)
	}
	allowed := func(u string) bool {
		for _, r := range rules {
			if regexp.MustCompile(r).MatchString(u) {
				return true
			}
		}
		return false
	}
	base := "https://roundlane723396.contest.codeforces.com"
	for _, path := range []string{"/", "/enter?back=%2Fgroup%2Ftqy1SBMbAa", "/group/tqy1SBMbAa/contests", "/group/tqy1SBMbAa/contest/723396", "/group/tqy1SBMbAa/contest/723396/problem/A", "/group/tqy1SBMbAa/contest/723396/submit", "/group/tqy1SBMbAa/contest/723396/my", "/group/tqy1SBMbAa/contest/723396/standings/groupmates/true", "/group/tqy1SBMbAa/data/customtest", "/group/tqy1SBMbAa/data/customtest?locale=ru", "/s/1/scripts/jquery.js", "/data/submissionStatus"} {
		if !allowed(base + path) {
			t.Errorf("blocked needed %s", path)
		}
	}
	for _, u := range []string{"https://codeforces.com/", "https://codeforces.com/blog/entry/1", "https://codeforces.com/problemset", "https://other.contest.codeforces.com/", "https://google.com/", "https://chatgpt.com/", base + "/group/tqy1SBMbAa/blog", base + "/group/tqy1SBMbAa/contest/723397", base + "/group/tqy1SBMbAa/contest/7233960", base + "/group/other/contest/723396", base + "/group/other/data/customtest", base + "/group/tqy1SBMbAa/data/customtest-other", base + "/group/tqy1SBMbAa/data/customtest/extra", base + "/profile/user1", base + "/problemset", base + ".evil.test/group/tqy1SBMbAa/contest/723396"} {
		if allowed(u) {
			t.Errorf("allowed unrelated %s", u)
		}
	}
	for _, u := range []string{base, base + "/group/tqy1SBMbAa/contests", TestContest + "/../723397", TestContest + "?x=1", base + "/group/tqy1SBMbAa/contest/%37%32%33%33%39%36"} {
		if _, err := GroupURL(u); err == nil {
			t.Errorf("invalid contest accepted %s", u)
		}
	}
}

// Paths used by the actual Codeforces group pages and PushStream client.
// Administrative actions and unrelated groups must remain unavailable.
func TestParticipantServiceRequests(t *testing.T) {
	rules, err := AllowedForContest(TestContest)
	if err != nil {
		t.Fatal(err)
	}
	allowed := func(u string) bool {
		for _, r := range rules {
			if regexp.MustCompile(r).MatchString(u) {
				return true
			}
		}
		return false
	}
	base := "https://roundlane723396.contest.codeforces.com"
	for _, endpoint := range []string{"customtest", "submitSource", "judgeProtocol", "submissionVerdict", "standings", "contests", "newProblemQuestion", "changeProblemQuestionOrAnnouncementDataPage"} {
		for _, suffix := range []string{"", "?locale=ru"} {
			if !allowed(base + "/group/tqy1SBMbAa/data/" + endpoint + suffix) {
				t.Errorf("blocked participant endpoint %s%s", endpoint, suffix)
			}
		}
		for _, path := range []string{"/group/other/data/" + endpoint, "/group/tqy1SBMbAa/data/" + endpoint + "-extra", "/group/tqy1SBMbAa/data/" + endpoint + "/extra"} {
			if allowed(base + path) {
				t.Errorf("allowed unrelated endpoint %s", path)
			}
		}
	}
	for _, u := range []string{
		"wss://roundlane723396.contest.codeforces.com/ws/channel?_=1",
		base + "/ws/channel?_=1", base + "/ev/channel?_=1", base + "/lp/channel.b1?_=1",
	} {
		if !allowed(u) {
			t.Errorf("blocked live update %s", u)
		}
	}
	for _, u := range []string{
		base + "/group/tqy1SBMbAa/data/changeParticipantType", base + "/group/tqy1SBMbAa/data/answerProblemQuestion",
		base + "/group/tqy1SBMbAa/data/unknown", base + "/manifest.json", base + "/pub/channel",
		"wss://other.contest.codeforces.com/ws/channel", "wss://roundlane723396.contest.codeforces.com.evil.test/ws/channel",
		"wss://roundlane723396.contest.codeforces.com/other/channel", "ws://roundlane723396.contest.codeforces.com/ws/channel",
		"https://www.googletagmanager.com/gtag/js", "https://google.com/", "https://chatgpt.com/",
	} {
		if allowed(u) {
			t.Errorf("allowed unrelated or administrative URL %s", u)
		}
	}
}
