package core

import (
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"math/big"
	"net/url"
	"regexp"
	"strings"

	"howett.net/plist"
)

const (
	StartURL    = "http://127.0.0.1:18765/"
	DefaultCode = "1234"
)

var groupID = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

var UsabilityKeys = []string{"allowFind", "enableZoomPage", "enableZoomText", "showTime",
	"browserWindowAllowReload", "newBrowserWindowAllowReload", "showReloadWarning",
	"newBrowserWindowShowReloadWarning", "enableBrowserWindowToolbar", "allowBrowsingBackForward"}

const TestContest = "https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723396"

var contestPath = regexp.MustCompile(`^/group/[A-Za-z0-9_-]+/contest/[1-9][0-9]*/?$`)
var contestHost = regexp.MustCompile(`^[a-z][a-z0-9]{2,19}\.contest\.codeforces\.com$`)

func GroupURL(input string) (string, error) {
	text := strings.TrimSpace(input)
	if strings.HasPrefix(text, "codeforces.com/") {
		text = "https://" + text
	}
	u, err := url.Parse(text)
	if err != nil || u.Scheme != "https" || (u.Hostname() != "codeforces.com" && !contestHost.MatchString(u.Hostname())) || u.Port() != "" || u.User != nil || u.Fragment != "" || u.RawQuery != "" || !contestPath.MatchString(u.EscapedPath()) {
		return "", errors.New("нужна точная ссылка https://…/group/…/contest/…")
	}
	return u.String(), nil
}

func AllowedForContest(contest string) ([]string, error) {
	checked, err := GroupURL(contest)
	if err != nil {
		return nil, err
	}
	u, _ := url.Parse(checked)
	path := strings.TrimRight(u.Path, "/")
	parts := strings.Split(path, "/")
	base := `^https://` + regexp.QuoteMeta(u.Hostname())
	group := regexp.QuoteMeta("/group/" + parts[2])
	root := base + `/([?#].*)?$`
	if u.Hostname() == "codeforces.com" {
		root = `^$`
	}
	rules := []string{
		`^http://127\.0\.0\.1:18765/`,
		base + regexp.QuoteMeta(path) + `/?([?#].*)?$`,
		base + regexp.QuoteMeta(path) + `/`,
		base + group + `/?([?#].*)?$`,
		base + group + `/contests/?([?#].*)?$`,
		base + `/enter([?#].*)?$`,
		base + `/[a-f0-9]+/logout([?#].*)?$`,
		root,
		`^blob:https://` + regexp.QuoteMeta(u.Hostname()) + `/`,
		`^https://assets\.codeforces\.com/`,
		`^https://challenges\.cloudflare\.com/`,
		`^https://cpp\.sh/`,
	}
	// Participant AJAX routes live under the group, outside /contest/.
	for _, endpoint := range []string{"customtest", "submitSource", "judgeProtocol", "submissionVerdict", "standings", "contests", "newProblemQuestion", "changeProblemQuestionOrAnnouncementDataPage"} {
		rules = append(rules, base+group+`/data/`+endpoint+`([?#].*)?$`)
	}
	// PushStream receives verdicts and announcements on the selected host.
	for _, endpoint := range []string{"ws", "ev", "lp"} {
		rules = append(rules, base+"/"+endpoint+"/")
	}
	rules = append(rules, `^wss://`+regexp.QuoteMeta(u.Hostname())+`/ws/`)
	for _, dir := range []string{"s", "data", "cdn-cgi"} {
		rules = append(rules, base+"/"+dir+"/")
	}
	for _, ext := range []string{"css", "js", "png", "jpg", "jpeg", "gif", "svg", "ico", "woff", "woff2", "ttf", "eot"} {
		rules = append(rules, base+`/[^?#]*\.`+ext+`([?#].*)?$`)
	}
	return rules, nil
}

func ValidCode(code string) bool {
	if len(code) < 4 || len(code) > 32 {
		return false
	}
	for _, c := range code {
		if !(c >= '0' && c <= '9' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z') {
			return false
		}
	}
	return true
}

// GenerateCode uses unbiased cryptographic randomness and avoids lookalike characters.
func GenerateCode() (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
	code := make([]byte, 12)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", err
		}
		code[i] = alphabet[n.Int64()]
	}
	return string(code), nil
}

func PasswordHash(code string) string {
	sum := sha256.Sum256([]byte(code))
	return fmt.Sprintf("%X", sum)
}

func MakeProfile(template []byte, code string) ([]byte, error) {
	if !ValidCode(code) {
		return nil, errors.New("пароль: 4–32 латинских букв или цифр")
	}
	return MakeProfileWithHash(template, PasswordHash(code))
}

func MakeProfileWithHash(template []byte, hash string, contestURLs ...string) ([]byte, error) {
	if !ValidPasswordHash(hash) {
		return nil, errors.New("неверный хеш кода выхода")
	}
	hash = strings.ToUpper(hash)
	contest := TestContest
	if len(contestURLs) > 0 {
		contest = contestURLs[0]
	}
	allowed, err := AllowedForContest(contest)
	if err != nil {
		return nil, err
	}
	var settings map[string]interface{}
	if _, err := plist.Unmarshal(template, &settings); err != nil {
		return nil, fmt.Errorf("неверный шаблон SEB: %w", err)
	}
	settings["allowQuit"] = true
	for _, key := range UsabilityKeys {
		settings[key] = true
	}
	settings["showQuitButton"] = true
	settings["hashedQuitPassword"] = hash
	settings["startURL"] = StartURL
	settings["sebConfigPurpose"] = 0
	settings["sebServicePolicy"] = 2
	settings["sebServiceIgnore"] = false
	settings["URLFilterEnable"] = true
	settings["URLFilterEnableContentFilter"] = true
	settings["allowPreferencesWindow"] = false
	settings["browserWindowAllowAddressBar"] = false
	settings["newBrowserWindowAllowAddressBar"] = false
	settings["allowDownloads"] = false
	settings["allowUploads"] = false
	settings["downloadAndOpenSebConfig"] = false
	rules := make([]map[string]interface{}, 0, len(allowed))
	for _, expression := range allowed {
		rules = append(rules, map[string]interface{}{
			"action": 1, "active": true, "expression": expression, "regex": true,
		})
	}
	settings["URLFilterRules"] = rules
	data, err := plist.Marshal(settings, plist.XMLFormat)
	if err != nil {
		return nil, err
	}
	if !ProfileMatchesHash(data, hash, contest) {
		return nil, errors.New("не удалось проверить выход из SEB")
	}
	return data, nil
}

func ProfileIsRecoverable(data []byte, code string) bool {
	return ValidCode(code) && ProfileMatchesHash(data, PasswordHash(code))
}

func ProfileMatchesHash(data []byte, hash string, contestURLs ...string) bool {
	contest := TestContest
	if len(contestURLs) > 0 {
		contest = contestURLs[0]
	}
	allowed, err := AllowedForContest(contest)
	if err != nil {
		return false
	}
	if !ValidPasswordHash(hash) {
		return false
	}
	var settings map[string]interface{}
	if _, err := plist.Unmarshal(data, &settings); err != nil {
		return false
	}
	checkBool := func(key string, want bool) bool { got, ok := settings[key].(bool); return ok && got == want }
	for _, key := range UsabilityKeys {
		if !checkBool(key, true) {
			return false
		}
	}
	if !checkBool("allowQuit", true) || !checkBool("showQuitButton", true) ||
		!checkBool("URLFilterEnable", true) || !checkBool("URLFilterEnableContentFilter", true) ||
		!checkBool("allowPreferencesWindow", false) || !checkBool("browserWindowAllowAddressBar", false) ||
		!checkBool("newBrowserWindowAllowAddressBar", false) || !checkBool("allowDownloads", false) ||
		!checkBool("allowUploads", false) || !checkBool("downloadAndOpenSebConfig", false) ||
		fmt.Sprint(settings["sebServicePolicy"]) != "2" || !checkBool("sebServiceIgnore", false) ||
		settings["hashedQuitPassword"] != strings.ToUpper(hash) || settings["startURL"] != StartURL {
		return false
	}
	rawRules, ok := settings["URLFilterRules"].([]interface{})
	if !ok || len(rawRules) != len(allowed) {
		return false
	}
	for i, raw := range rawRules {
		rule, ok := raw.(map[string]interface{})
		if !ok || rule["active"] != true || rule["regex"] != true ||
			fmt.Sprint(rule["action"]) != "1" || rule["expression"] != allowed[i] {
			return false
		}
	}
	return true
}
