Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!include "StrFunc.nsh"
${StrStr}
${UnStrStr}
!ifndef ROUNDLANE_DIST
!define ROUNDLANE_DIST "dist"
!endif
Name "Roundlane"
!ifndef ROUNDLANE_INSTALLER_OUTPUT
!define ROUNDLANE_INSTALLER_OUTPUT "${ROUNDLANE_DIST}/Roundlane 3.0 Setup.exe"
!endif
OutFile "${ROUNDLANE_INSTALLER_OUTPUT}"
InstallDir "$PROGRAMFILES64\Roundlane"
RequestExecutionLevel admin
!ifdef ROUNDLANE_NON_SOLID
SetCompressor lzma
!else
SetCompressor /SOLID lzma
!endif
Icon "app.ico"
UninstallIcon "app.ico"
BrandingText "Roundlane"
ShowInstDetails show
Var Result
Var Details
!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "Roundlane установлен"
!define MUI_FINISHPAGE_TEXT "Встроенный экзаменационный режим установлен вместе с приложением. Запустите Roundlane из меню «Пуск»."
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "Нужна 64-битная Windows 10 или 11."
    Abort
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP "Нужна Windows 10 или 11."
    Abort
  ${EndIf}
  nsExec::ExecToStack '"$SYSDIR\tasklist.exe" /FI "IMAGENAME eq Roundlane.Runtime.exe" /NH'
  Pop $Result
  Pop $Details
  ${StrStr} $0 $Details "Roundlane.Runtime.exe"
  ${If} $0 != ""
    MessageBox MB_ICONSTOP "Сначала завершите соревнование Roundlane штатным выходом."
    Abort
  ${EndIf}
FunctionEnd

Function CheckResult
  ${If} $Result == 3010
    SetRebootFlag true
    MessageBox MB_ICONINFORMATION "Перезагрузите Windows и повторите установку. Экзамен автоматически не запускается."
    SetErrorLevel 3010
    Abort
  ${ElseIf} $Result != 0
    MessageBox MB_ICONSTOP "Компонент не установлен: $Result. Установка остановлена."
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Section "Roundlane"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File "dependencies/vc_redist.x64.exe"
  File "dependencies/ndp48-x86-x64-allos-enu.exe"
  File "prepare-update.ps1"
  SetRegView 64
  ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
  ${If} $0 < 528040
    ExecWait '"$PLUGINSDIR\ndp48-x86-x64-allos-enu.exe" /norestart' $Result
    Call CheckResult
  ${EndIf}
  ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Installed"
  ${If} $0 != 1
    ExecWait '"$PLUGINSDIR\vc_redist.x64.exe" /install /passive /norestart' $Result
    Call CheckResult
  ${EndIf}
  nsExec::ExecToLog /TIMEOUT=60000 '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\prepare-update.ps1" -InstallDir "$INSTDIR"'
  Pop $Result
  Call CheckResult
  SetOutPath "$INSTDIR"
  File "${ROUNDLANE_DIST}/Roundlane.exe"
  File "${ROUNDLANE_DIST}/RoundlaneHub.exe"
  File "${ROUNDLANE_DIST}/contest.seb"
  File "${ROUNDLANE_DIST}/competition.roundlane"
  File "${ROUNDLANE_DIST}/starter.cpp"
  File "${ROUNDLANE_DIST}/LICENSE-SEB.txt"
  File "${ROUNDLANE_DIST}/ROUNDLANE-NOTICE.txt"
  SetOutPath "$INSTDIR\hub"
  File "${ROUNDLANE_DIST}/hub/index.html"
  File "${ROUNDLANE_DIST}/hub/app.js"
  SetOutPath "$INSTDIR\runtime"
  File /r "${ROUNDLANE_DIST}/runtime/*"
  SetOutPath "$INSTDIR\sources"
  File "${ROUNDLANE_DIST}/RoundlaneWindowsSource.zip"
  nsExec::ExecToLog '"$SYSDIR\sc.exe" create Roundlane binPath= "\$\"$INSTDIR\runtime\Roundlane.Service.exe\$\"" start= auto DisplayName= "Roundlane Exam Service"'
  Pop $Result
  ${If} $Result != 0
  ${AndIf} $Result != 1073
    Call CheckResult
  ${EndIf}
  nsExec::ExecToLog '"$SYSDIR\sc.exe" config Roundlane binPath= "\$\"$INSTDIR\runtime\Roundlane.Service.exe\$\"" start= auto'
  Pop $Result
  Call CheckResult
  nsExec::ExecToLog '"$SYSDIR\sc.exe" description Roundlane $\"Roundlane exam restrictions and automatic desktop recovery$\"'
  Pop $Result
  nsExec::ExecToLog '"$SYSDIR\sc.exe" failure Roundlane reset= 86400 actions= restart/5000/restart/5000/restart/5000'
  Pop $Result
  Call CheckResult
  nsExec::ExecToLog '"$SYSDIR\sc.exe" start Roundlane'
  Pop $Result
  Call CheckResult
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  SetShellVarContext all
  CreateDirectory "$SMPROGRAMS\Roundlane"
  CreateShortCut "$SMPROGRAMS\Roundlane\Roundlane.lnk" "$INSTDIR\Roundlane.exe"
  CreateShortCut "$SMPROGRAMS\Roundlane\Восстановление Windows.lnk" "$INSTDIR\runtime\Roundlane.Recovery.exe"
  CreateShortCut "$SMPROGRAMS\Roundlane\Удалить Roundlane.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortCut "$DESKTOP\Roundlane.lnk" "$INSTDIR\Roundlane.exe"
  WriteRegStr HKLM "Software\Classes\.roundlane" "" "Roundlane.Competition"
  WriteRegStr HKLM "Software\Classes\Roundlane.Competition" "" "Roundlane — соревнование"
  WriteRegStr HKLM "Software\Classes\Roundlane.Competition\DefaultIcon" "" "$INSTDIR\Roundlane.exe,0"
  WriteRegStr HKLM "Software\Classes\Roundlane.Competition\shell\open\command" "" '$\"$INSTDIR\Roundlane.exe$\" --settings $\"%1$\"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayName" "Roundlane"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayVersion" "3.10.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayIcon" "$INSTDIR\Roundlane.exe"
SectionEnd

Section "Uninstall"
  nsExec::ExecToStack '"$SYSDIR\tasklist.exe" /FI "IMAGENAME eq Roundlane.Runtime.exe" /NH'
  Pop $Result
  Pop $Details
  ${UnStrStr} $0 $Details "Roundlane.Runtime.exe"
  ${If} $0 != ""
    MessageBox MB_ICONSTOP "Сначала завершите соревнование Roundlane штатным выходом."
    Abort
  ${EndIf}
  nsExec::ExecToLog '"$SYSDIR\sc.exe" stop Roundlane'
  Pop $Result
  Sleep 2000
  nsExec::ExecToLog '"$SYSDIR\sc.exe" delete Roundlane'
  Pop $Result
  SetShellVarContext all
  DeleteRegKey HKLM "Software\Classes\Roundlane.Competition"
  ReadRegStr $0 HKLM "Software\Classes\.roundlane" ""
  ${If} $0 == "Roundlane.Competition"
    DeleteRegKey HKLM "Software\Classes\.roundlane"
  ${EndIf}
  Delete "$DESKTOP\Roundlane.lnk"
  Delete "$SMPROGRAMS\Roundlane\Roundlane.lnk"
  Delete "$SMPROGRAMS\Roundlane\Восстановление Windows.lnk"
  Delete "$SMPROGRAMS\Roundlane\Удалить Roundlane.lnk"
  RMDir "$SMPROGRAMS\Roundlane"
  Delete "$INSTDIR\Roundlane.exe"
  Delete "$INSTDIR\RoundlaneHub.exe"
  Delete "$INSTDIR\contest.seb"
  Delete "$INSTDIR\competition.roundlane"
  Delete "$INSTDIR\starter.cpp"
  Delete "$INSTDIR\LICENSE-SEB.txt"
  Delete "$INSTDIR\ROUNDLANE-NOTICE.txt"
  RMDir /r "$INSTDIR\runtime"
  RMDir /r "$INSTDIR\sources"
  Delete "$INSTDIR\hub\index.html"
  Delete "$INSTDIR\hub\app.js"
  RMDir "$INSTDIR\hub"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane"
SectionEnd
