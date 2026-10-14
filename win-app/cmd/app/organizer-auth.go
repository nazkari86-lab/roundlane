package main

import (
	"github.com/lxn/walk"
	. "github.com/lxn/walk/declarative"
	"roundlane/windows/core"
)

// The participant package cannot enter manual configuration without its own code.
func authorizeOrganizer(hash string) bool {
	var dialog *walk.Dialog
	var code *walk.LineEdit
	var status *walk.TextLabel
	var cancel, accept *walk.PushButton
	result, err := (Dialog{
		AssignTo: &dialog, Title: "Режим организатора", Size: Size{Width: 410, Height: 220},
		MinSize: Size{Width: 390, Height: 200}, FixedSize: true,
		DefaultButton: &accept, CancelButton: &cancel,
		Layout: VBox{Margins: Margins{Left: 20, Top: 20, Right: 20, Bottom: 20}, Spacing: 12},
		Children: []Widget{
			TextLabel{Text: "Введите код организатора для этого приложения"},
			LineEdit{AssignTo: &code, PasswordMode: true, MaxLength: 32},
			TextLabel{AssignTo: &status, Text: ""},
			Composite{Layout: HBox{MarginsZero: true, Spacing: 10}, Children: []Widget{
				PushButton{AssignTo: &cancel, Text: "Отмена", OnClicked: func() { dialog.Cancel() }},
				HSpacer{},
				PushButton{AssignTo: &accept, Text: "Открыть", OnClicked: func() {
					if core.VerifyOrganizerCode(code.Text(), hash) {
						code.SetText("")
						dialog.Accept()
					} else {
						status.SetText("Неверный код")
						code.SetText("")
						code.SetFocus()
					}
				}},
			}},
		},
	}).Run(nil)
	return err == nil && result == walk.DlgCmdOK
}
