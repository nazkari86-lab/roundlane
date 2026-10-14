package core

import (
	"html"
	"net/url"
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestHubLinksReadyWithoutScript(t *testing.T) {
	template, err := os.ReadFile("../../hub/index.html")
	if err != nil {
		t.Fatal(err)
	}
	starter := []byte("#include <iostream>\nint main(){std::cout << \"a+b & c\";}\n")
	group := "https://codeforces.com/group/Test123/contest/42"
	page, err := RenderHub(template, group, starter)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(page), "<script") || strings.Contains(string(page), "__ROUNDLANE_") || strings.Contains(string(page), "aria-disabled=\"true\"") {
		t.Fatal("links depend on script or placeholders")
	}
	links := regexp.MustCompile(`id="(?:group|compiler)-link" href="([^"]+)"`).FindAllSubmatch(page, -1)
	if len(links) != 2 || html.UnescapeString(string(links[0][1])) != group {
		t.Fatal("group link changed")
	}
	compiler, err := url.Parse(html.UnescapeString(string(links[1][1])))
	if err != nil || compiler.Scheme != "https" || compiler.Host != "cpp.sh" || compiler.Query().Get("source") != string(starter) {
		t.Fatal("starter lost in compiler link")
	}
	if _, err = RenderHub(template, "https://evil.test/group/Test123", starter); err == nil {
		t.Fatal("foreign group accepted")
	}
}
