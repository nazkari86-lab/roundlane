package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/lxn/walk"
	. "github.com/lxn/walk/declarative"
	"golang.org/x/sys/windows/svc/mgr"
	"roundlane/windows/core"
	"roundlane/windows/secretstore"
	"roundlane/windows/winproc"
)

func installDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "."
	}
	return filepath.Dir(exe)
}

func runtimePath() string { return core.RuntimePath(installDir()) }

func examServiceReady() error {
	m, err := mgr.Connect()
	if err != nil {
		return errors.New("Не удалось проверить службу Roundlane")
	}
	defer m.Disconnect()
	s, err := m.OpenService("Roundlane")
	if err != nil {
		return errors.New("Служба Roundlane не установлена. Запустите полный установщик с администратором")
	}
	defer s.Close()
	config, err := s.Config()
	if err != nil {
		return err
	}
	expected := filepath.Join(installDir(), "runtime", "Roundlane.Service.exe")
	if !strings.EqualFold(strings.Trim(config.BinaryPathName, "\""), expected) {
		return errors.New("Служба Roundlane принадлежит другой установке. Повторите установку")
	}
	status, err := s.Query()
	if err != nil {
		return err
	}
	if status.State != 4 {
		return errors.New("Служба Roundlane остановлена. Организатор должен запустить службу перед экзаменом")
	}
	return nil
}

func lastGroupPath() string {
	base, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(base, "Roundlane", "group.txt")
}

func lastGroup() string {
	base, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	for _, name := range []string{"Roundlane", "Dulat Arena", "Dulat Contest"} {
		if data, err := os.ReadFile(filepath.Join(base, name, "group.txt")); err == nil {
			return strings.TrimSpace(string(data))
		}
	}
	return ""
}

func saveGroup(group string) {
	path := lastGroupPath()
	if path == "" {
		return
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return
	}
	_ = os.WriteFile(path, []byte(group+"\n"), 0600)
}

func startContest(group, quitHash string) error {
	if err := core.VerifyRuntime(installDir()); err != nil {
		return err
	}
	if err := examServiceReady(); err != nil {
		return err
	}
	running, err := winproc.Running(core.RuntimeExecutable)
	if err != nil {
		return fmt.Errorf("не удалось проверить состояние Roundlane: %w", err)
	}
	if running {
		return errors.New("Соревнование уже открыто. Сначала завершите текущую сессию.")
	}
	root := installDir()
	for _, name := range []string{"RoundlaneHub.exe", "hub/index.html", "hub/app.js", "starter.cpp", "contest.seb"} {
		if _, err := os.Stat(filepath.Join(root, name)); err != nil {
			return fmt.Errorf("в пакете отсутствует %s; установите приложение заново", name)
		}
	}
	template, err := os.ReadFile(filepath.Join(root, "contest.seb"))
	if err != nil {
		return err
	}
	profile, err := core.MakeProfileWithHash(template, quitHash, group)
	if err != nil {
		return err
	}
	temporary, err := os.MkdirTemp("", "Roundlane-")
	if err != nil {
		return err
	}
	profilePath := filepath.Join(temporary, "contest.seb")
	if err := os.WriteFile(profilePath, profile, 0600); err != nil {
		_ = os.RemoveAll(temporary)
		return err
	}
	helper, err := startHub(group, temporary)
	if err != nil {
		return err
	}
	readyPath := filepath.Join(temporary, "session-ready")
	runtime := exec.Command(runtimePath(), profilePath)
	runtime.Dir = filepath.Dir(runtimePath())
	runtime.Env = append(os.Environ(), "ROUNDLANE_READY_FILE="+readyPath, "ROUNDLANE_CONTEST_URL="+group)
	if err := runtime.Start(); err != nil {
		_ = helper.Process.Kill()
		_ = os.RemoveAll(temporary)
		return fmt.Errorf("не удалось открыть встроенный режим Roundlane: %w", err)
	}
	exited := make(chan error, 1)
	go func() { exited <- runtime.Wait() }()
	for {
		if ready, err := os.ReadFile(readyPath); err == nil && string(ready) == "session-ready" {
			return nil
		}
		select {
		case <-exited:
			_ = helper.Process.Kill()
			_ = os.RemoveAll(temporary)
			return errors.New("Встроенный режим завершился до начала соревнования. Проверьте журналы Roundlane")
		case <-time.After(250 * time.Millisecond):
		}
	}
}

func readiness() error {
	if err := core.VerifyRuntime(installDir()); err != nil {
		return err
	}
	if err := examServiceReady(); err != nil {
		return err
	}
	if running, err := winproc.Running(core.RuntimeExecutable); err != nil {
		return errors.New("Не удалось проверить текущую сессию. Откройте Roundlane заново")
	} else if running {
		return errors.New("Завершите текущую сессию Roundlane")
	}
	for _, name := range []string{"RoundlaneHub.exe", "hub/index.html", "hub/app.js", "starter.cpp", "contest.seb"} {
		info, err := os.Stat(filepath.Join(installDir(), name))
		if err != nil || info.IsDir() {
			return errors.New("Приложение повреждено. Установите Roundlane заново")
		}
	}
	template, err := os.ReadFile(filepath.Join(installDir(), "contest.seb"))
	if err == nil {
		_, err = core.MakeProfile(template, core.DefaultCode)
	}
	if err != nil {
		return errors.New("Не удалось проверить код выхода. Установите Roundlane заново")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:18765")
	if err != nil {
		return errors.New("Стартовая страница занята. Завершите другую сессию")
	}
	return listener.Close()
}

func confirmStart(owner *walk.MainWindow, group, codeDescription string) bool {
	var dialog *walk.Dialog
	var back *walk.PushButton
	result, err := (Dialog{
		AssignTo:     &dialog,
		Title:        "Начать соревнование?",
		Icon:         owner.Icon(),
		Size:         Size{Width: 510, Height: 255},
		MinSize:      Size{Width: 480, Height: 255},
		FixedSize:    true,
		CancelButton: &back,
		Layout:       VBox{Margins: Margins{Left: 24, Top: 24, Right: 24, Bottom: 24}, Spacing: 14},
		Children: []Widget{
			TextLabel{Text: group, MinSize: Size{Width: 420}},
			TextLabel{Text: codeDescription, Font: Font{PointSize: 14, Bold: true}},
			TextLabel{Text: "Выход: Ctrl+Q → код. Рабочий стол будет заблокирован.", MinSize: Size{Width: 420}},
			VSpacer{},
			Composite{Layout: HBox{MarginsZero: true, Spacing: 12}, Children: []Widget{
				PushButton{AssignTo: &back, Text: "Назад", OnClicked: func() { dialog.Cancel() }},
				HSpacer{},
				PushButton{Text: "Начать соревнование", OnClicked: func() { dialog.Accept() }},
			}},
		},
	}).Run(owner)
	return err == nil && result == walk.DlgCmdOK
}

func main() {
	options, argumentError := core.ParseLaunchArguments(os.Args[1:])
	if argumentError != nil {
		walk.MsgBox(nil, "Неверная команда Roundlane", argumentError.Error(), walk.MsgBoxOK|walk.MsgBoxIconError)
		return
	}
	settingsPath, checkPath, reportPath := options.SettingsPath, options.CheckPath, options.ReportPath
	checkNative, organizerTools := options.CheckRuntime, options.OrganizerTools
	if checkNative {
		os.Exit(checkRuntime(reportPath))
	}
	if checkPath != "" {
		os.Exit(checkCompetition(checkPath, reportPath))
	}
	var bundled core.Competition
	bundlePath := filepath.Join(installDir(), "competition.roundlane")
	if _, err := os.Stat(bundlePath); err == nil {
		bundled, err = loadCompetition(bundlePath)
		if err != nil {
			walk.MsgBox(nil, "Не удалось открыть соревнование", err.Error(), walk.MsgBoxOK|walk.MsgBoxIconError)
			return
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		walk.MsgBox(nil, "Не удалось открыть соревнование", err.Error(), walk.MsgBoxOK|walk.MsgBoxIconError)
		return
	}
	if settingsPath == "" && !organizerTools {
		var err error
		settingsPath, err = core.DefaultSettingsPath(bundlePath, participantPath())
		if err != nil {
			walk.MsgBox(nil, "Не удалось открыть соревнование", err.Error(), walk.MsgBoxOK|walk.MsgBoxIconError)
			return
		}
	}
	var chosen core.Competition
	if settingsPath != "" {
		c, err := loadCompetition(settingsPath)
		if err != nil {
			walk.MsgBox(nil, "Не удалось открыть соревнование", err.Error(), walk.MsgBoxOK|walk.MsgBoxIconError)
			return
		}
		chosen = c
		if c.IsParticipant() && !organizerTools {
			runParticipant(c)
			return
		}
	}
	if core.RequiresOrganizerAuthorization(bundled, chosen, organizerTools) && !authorizeOrganizer(bundled.QuitPasswordHash) {
		return
	}
	initialCode, restoreError := secretstore.Load()
	if errors.Is(restoreError, os.ErrNotExist) {
		initialCode = core.DefaultCode
		restoreError = nil
	}
	if settingsPath != "" {
		initialCode = core.DefaultCode
		restoreError = nil
	}
	var mw *walk.MainWindow
	var groupField, codeField *walk.LineEdit
	var status *walk.TextLabel
	var startButton, generateButton, copyButton *walk.PushButton
	var openButton, saveButton *walk.PushButton
	var loaded *core.Competition
	var settingsError error
	busy := false
	checked := false
	var runtimeError error
	var refresh func()
	refresh = func() {
		if groupField == nil || codeField == nil || startButton == nil || status == nil {
			return
		}
		_, groupError := core.GroupURL(groupField.Text())
		validCode := loaded != nil || core.ValidCode(codeField.Text())
		ready := checked && runtimeError == nil && settingsError == nil && groupError == nil && validCode
		startButton.SetEnabled(!busy && ready)
		copyButton.SetEnabled(!busy && loaded == nil && validCode)
		generateButton.SetEnabled(!busy && loaded == nil)
		if saveButton != nil {
			saveButton.SetEnabled(!busy && loaded == nil && groupError == nil && validCode && settingsError == nil)
		}
		if busy {
			return
		}
		message := "Готово к старту"
		invalid := false
		switch {
		case settingsError != nil:
			message = settingsError.Error()
			invalid = true
		case !checked:
			message = "Проверяю приложение…"
		case runtimeError != nil:
			message = runtimeError.Error()
			invalid = true
		case strings.TrimSpace(groupField.Text()) == "":
			message = "Вставьте ссылку на соревнование"
		case groupError != nil:
			message = "Нужна ссылка /group/…/contest/…"
			invalid = true
		case !validCode:
			message = "Код: 4–32 латинских букв или цифр"
			if restoreError != nil {
				message = "Сохранённый код недоступен. Введите его снова"
			}
			invalid = true
		case loaded != nil:
			message = "Настройки загружены. Код выхода у организатора"
		}
		_ = status.SetText(message)
		if invalid {
			status.SetTextColor(walk.RGB(160, 35, 35))
		} else {
			status.SetTextColor(walk.RGB(65, 65, 65))
		}
	}
	setBusy := func(value bool) {
		busy = value
		groupField.SetEnabled(!value && loaded == nil)
		codeField.SetEnabled(!value && loaded == nil)
		openButton.SetEnabled(!value)
		refresh()
	}
	applySettings := func(path string) {
		c, err := loadCompetition(path)
		if err != nil {
			settingsError = err
			refresh()
			return
		}
		loaded = &c
		settingsError = nil
		_ = groupField.SetText(c.GroupURL)
		_ = codeField.SetText("У организатора")
		groupField.SetEnabled(false)
		codeField.SetEnabled(false)
		refresh()
	}
	icon, _ := walk.NewIconFromResourceId(2) // rsrc emits manifest 1, icon group 2.
	window := MainWindow{
		AssignTo: &mw,
		Title:    "Roundlane",
		Icon:     icon,
		Size:     Size{Width: 560, Height: 390},
		MinSize:  Size{Width: 500, Height: 390},
		Layout:   VBox{Margins: Margins{Left: 24, Top: 20, Right: 24, Bottom: 20}, Spacing: 8},
		Children: []Widget{
			TextLabel{Text: "Соревнование Codeforces"},
			LineEdit{AssignTo: &groupField, Text: lastGroup(), CueBanner: "https://…/group/…/contest/…", Accessibility: Accessibility{Name: "Ссылка на соревнование Codeforces"}, OnTextChanged: func() { refresh() }},
			VSpacer{Size: 10},
			TextLabel{Text: "Код выхода"},
			Composite{Layout: HBox{MarginsZero: true, Spacing: 8}, Children: []Widget{
				LineEdit{AssignTo: &codeField, Text: initialCode, MaxSize: Size{Width: 180}, MinSize: Size{Width: 160}, Font: Font{PointSize: 12}, Accessibility: Accessibility{Name: "Код выхода организатора"}, OnTextChanged: func() { refresh() }},
				PushButton{AssignTo: &generateButton, Text: "Новый код", ToolTipText: "Создать случайный код из 12 букв и цифр", OnClicked: func() {
					previous := codeField.Text()
					for {
						next, err := core.GenerateCode()
						if err != nil {
							_ = status.SetText("Не удалось создать код. Введите его вручную")
							return
						}
						if next != previous {
							_ = codeField.SetText(next)
							break
						}
					}
					refresh()
				}},
				PushButton{AssignTo: &copyButton, Text: "Копировать", OnClicked: func() {
					if err := walk.Clipboard().SetText(codeField.Text()); err != nil {
						_ = status.SetText("Не удалось скопировать код. Выделите его и нажмите Ctrl+C")
					} else {
						_ = status.SetText("Код скопирован")
					}
				}},
				HSpacer{},
			}},
			Composite{Layout: HBox{MarginsZero: true, Spacing: 8}, Children: []Widget{
				PushButton{AssignTo: &openButton, Text: "Открыть настройки", Accessibility: Accessibility{Name: "Открыть общий файл соревнования"}, OnClicked: func() {
					dlg := walk.FileDialog{Title: "Открыть настройки соревнования", Filter: "Настройки Roundlane (*.roundlane)|*.roundlane"}
					ok, err := dlg.ShowOpen(mw)
					if err != nil {
						_ = status.SetText("Не удалось открыть диалог выбора файла")
						return
					}
					if ok {
						applySettings(dlg.FilePath)
					}
				}},
				PushButton{AssignTo: &saveButton, Text: "Сохранить настройки", Accessibility: Accessibility{Name: "Сохранить общий файл соревнования"}, OnClicked: func() {
					if loaded != nil {
						return
					}
					c, err := core.NewCompetition(groupField.Text(), codeField.Text())
					if err != nil {
						refresh()
						return
					}
					if len(codeField.Text()) < 12 && walk.MsgBox(mw, "Короткий код можно подобрать по файлу", "Файл содержит SHA-256 кода. Для соревнования рекомендуем случайный код из 12 символов. Сохранить с коротким кодом?", walk.MsgBoxYesNo|walk.MsgBoxDefButton2|walk.MsgBoxIconWarning) != walk.DlgCmdYes {
						return
					}
					dlg := walk.FileDialog{Title: "Сохранить настройки соревнования", FilePath: "competition.roundlane", Filter: "Настройки Roundlane (*.roundlane)|*.roundlane"}
					ok, err := dlg.ShowSave(mw)
					if err != nil {
						_ = status.SetText("Не удалось открыть диалог сохранения")
						return
					}
					if !ok {
						return
					}
					path := dlg.FilePath
					if !strings.HasSuffix(strings.ToLower(path), ".roundlane") {
						path += ".roundlane"
					}
					if _, err := os.Stat(path); err == nil {
						if walk.MsgBox(mw, "Заменить настройки?", filepath.Base(path), walk.MsgBoxYesNo|walk.MsgBoxIconQuestion) != walk.DlgCmdYes {
							return
						}
					}
					if err := saveCompetition(path, c); err != nil {
						_ = status.SetText("Не удалось сохранить настройки: " + err.Error())
						return
					}
					if err := secretstore.Save(codeField.Text()); err != nil {
						_ = status.SetText("Настройки сохранены, но запомнить код на этом компьютере не удалось")
						return
					}
					_ = status.SetText("Настройки и код сохранены")
				}},
				HSpacer{},
			}},
			VSpacer{Size: 8},
			TextLabel{AssignTo: &status, MinSize: Size{Width: 440, Height: 34}, Accessibility: Accessibility{Name: "Состояние подготовки"}},
			VSpacer{},
			Composite{Layout: HBox{MarginsZero: true, Spacing: 12}, Children: []Widget{
				PushButton{Text: "Закрыть", OnClicked: func() { mw.Close() }},
				HSpacer{},
				PushButton{AssignTo: &startButton, Text: "Начать соревнование", Enabled: false, OnClicked: func() {
					group, err := core.GroupURL(groupField.Text())
					if err != nil || settingsError != nil || (loaded == nil && !core.ValidCode(codeField.Text())) {
						refresh()
						return
					}
					_ = groupField.SetText(group)
					code := codeField.Text()
					quitHash := core.PasswordHash(code)
					codeDescription := "Код выхода: " + code
					if loaded != nil {
						quitHash = loaded.QuitPasswordHash
						codeDescription = "Код выхода у организатора"
					}
					if !confirmStart(mw, group, codeDescription) {
						return
					}
					if loaded == nil {
						if err := secretstore.Save(code); err != nil {
							_ = status.SetText("Не удалось запомнить код на этом компьютере")
							return
						}
					}
					setBusy(true)
					_ = status.SetText("Начинаю соревнование…")
					go func() {
						err := startContest(group, quitHash)
						mw.Synchronize(func() {
							if err != nil {
								setBusy(false)
								_ = status.SetText(err.Error())
								return
							}
							saveGroup(group)
							mw.Close()
						})
					}()
				}},
			}},
		},
	}
	if err := window.Create(); err != nil {
		walk.MsgBox(nil, "Roundlane", err.Error(), walk.MsgBoxIconError)
		return
	}
	mw.Closing().Attach(func(canceled *bool, reason walk.CloseReason) {
		if loaded == nil && core.ValidCode(codeField.Text()) {
			if err := secretstore.Save(codeField.Text()); err != nil {
				walk.MsgBox(mw, "Код не сохранён", "После следующего запуска код нужно будет ввести снова. Сохраните его отдельно.", walk.MsgBoxOK|walk.MsgBoxIconWarning)
			}
			if group, err := core.GroupURL(groupField.Text()); err == nil {
				saveGroup(group)
			}
		}
	})
	groupField.SetFocus()
	if settingsPath != "" {
		applySettings(settingsPath)
	}
	refresh()
	go func() {
		problem := readiness()
		mw.Synchronize(func() { runtimeError = problem; checked = true; refresh() })
	}()
	mw.Run()
}
