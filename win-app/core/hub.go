package core

import (
	"errors"
	"html"
	"strings"
)

// RenderHub embeds ready links so local browser fetch delays cannot disable them.
func RenderHub(template []byte, group string, starter []byte) ([]byte, error) {
	group, err := GroupURL(group)
	if err != nil {
		return nil, err
	}
	page := string(template)
	if len(starter) == 0 || !strings.Contains(page, "__ROUNDLANE_GROUP_URL__") || !strings.Contains(page, "__ROUNDLANE_COMPILER_URL__") {
		return nil, errors.New("missing hub template or starter")
	}
	compiler := "https://www.onlinegdb.com/?new_lang=c%2B%2B20&sidebar=no"
	page = strings.ReplaceAll(page, "__ROUNDLANE_GROUP_URL__", html.EscapeString(group))
	page = strings.ReplaceAll(page, "__ROUNDLANE_COMPILER_URL__", html.EscapeString(compiler))
	return []byte(page), nil
}
