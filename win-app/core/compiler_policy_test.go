package core

import (
	"regexp"
	"testing"
)

func TestOnlineGDBCompilerPolicy(t *testing.T) {
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
	for _, u := range []string{"https://html-load.com/loader.min.js", "https://stg.html-load.com/loader.min.js", "https://www.onlinegdb.com/cdn-cgi/challenge-platform/scripts/jsd/main.js", "https://cdnjs.cloudflare.com/ajax/libs/bootstrap-select/1.12.4/js/bootstrap-select.min.js", "https://unpkg.com/react@17.0.2/umd/react.production.min.js", "https://cdn4.buysellads.net/pub/onlinegdb.js", "https://m.servedby-buysellads.com/monetization.js", "https://www.onlinegdb.com/?new_lang=c%2B%2B20&sidebar=no", "https://www.onlinegdb.com/online_c++_compiler", "https://www.onlinegdb.com/public/js/main.js?v=164", "https://www.onlinegdb.com/socket.io/?EIO=3&transport=polling", "wss://www.onlinegdb.com/socket.io/?EIO=3&transport=websocket", "https://in2.onlinegdb.com/socket.io/?transport=polling", "wss://in2.onlinegdb.com/socket.io/?transport=websocket", "https://www.onlinegdb.com/beautify", "blob:https://www.onlinegdb.com/abc"} {
		if !allowed(u) {
			t.Errorf("needed compiler request blocked: %s", u)
		}
	}
	for _, u := range []string{"https://html-load.com/", "https://stg.html-load.com/other.js", "https://cdn4.buysellads.net/", "https://cpp.sh/", "https://www.onlinegdb.com/askai", "https://www.onlinegdb.com/ai/models", "https://www.onlinegdb.com/share", "https://www.onlinegdb.com/myfiles", "https://www.onlinegdb.com/blog/", "https://question.onlinegdb.com/", "https://www.onlinegdb.com.evil.test/", "https://www.onlinegdb.com@evil.test/", "wss://evil.test/socket.io/", "https://unpkg.com/arbitrary-package/index.js"} {
		if allowed(u) {
			t.Errorf("unrelated request allowed: %s", u)
		}
	}
}
