package core

import (
	"crypto/subtle"
	"errors"
	"os"
	"strings"
)

type LaunchArguments struct {
	SettingsPath, CheckPath, ReportPath string
	CheckRuntime, OrganizerTools        bool
}

// An invalid diagnostic invocation must never fall through to exam startup.
func ParseLaunchArguments(args []string) (LaunchArguments, error) {
	var options LaunchArguments
	seen := map[string]bool{}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if seen[arg] {
			return options, errors.New("параметр указан повторно: " + arg)
		}
		seen[arg] = true
		switch arg {
		case "--organizer-tools":
			options.OrganizerTools = true
		case "--check-runtime":
			options.CheckRuntime = true
		case "--settings", "--check-settings", "--report":
			if i+1 >= len(args) || strings.HasPrefix(args[i+1], "--") || args[i+1] == "" {
				return options, errors.New("укажите файл после " + arg)
			}
			i++
			switch arg {
			case "--settings":
				if options.SettingsPath != "" {
					return options, errors.New("укажите один файл соревнования")
				}
				options.SettingsPath = args[i]
			case "--check-settings":
				options.CheckPath = args[i]
			case "--report":
				options.ReportPath = args[i]
			}
		default:
			if i == 0 && strings.HasSuffix(strings.ToLower(arg), ".roundlane") {
				options.SettingsPath = arg
			} else {
				return options, errors.New("неизвестный параметр запуска: " + arg)
			}
		}
	}
	diagnostic := options.CheckRuntime || options.CheckPath != ""
	if options.CheckRuntime && options.CheckPath != "" || diagnostic && (options.SettingsPath != "" || options.OrganizerTools) || options.ReportPath != "" && !diagnostic {
		return options, errors.New("несовместимые параметры запуска")
	}
	return options, nil
}

// The new sealed contest package wins over a previous contest's saved copy.
func DefaultSettingsPath(bundled, saved string) (string, error) {
	for _, path := range []string{bundled, saved} {
		if path == "" {
			continue
		}
		info, err := os.Stat(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return "", err
		}
		if !info.Mode().IsRegular() {
			return "", errors.New("настройки соревнования должны быть обычным файлом")
		}
		return path, nil
	}
	return "", nil
}

func RequiresOrganizerAuthorization(bundled Competition, chosen Competition, organizerTools bool) bool {
	return bundled.IsParticipant() && (organizerTools || !chosen.IsParticipant())
}

func VerifyOrganizerCode(code, hash string) bool {
	return ValidCode(code) && ValidPasswordHash(hash) && subtle.ConstantTimeCompare([]byte(PasswordHash(code)), []byte(strings.ToUpper(hash))) == 1
}
