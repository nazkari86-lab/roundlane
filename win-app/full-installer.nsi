Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WordFunc.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

Name "Roundlane"
OutFile "dist/Roundlane 2.6 Full Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Roundlane"
RequestExecutionLevel user
SetCompressor lzma
Icon "app.ico"
UninstallIcon "app.ico"
BrandingText "Roundlane"
ShowInstDetails show
Var SebPath
Var VendorResult

!define MUI_ABORTWARNING
!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "Roundlane установлен"
!define MUI_FINISHPAGE_TEXT "Откройте приложение и загрузите файл настроек или задайте группу и код выхода."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Открыть Roundlane"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenOrganizer
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "Roundlane требует 64-битную Windows 10 или 11."
    Abort
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP "Roundlane требует Windows 10 или 11."
    Abort
  ${EndIf}
FunctionEnd

Function FindSEB
  StrCpy $SebPath ""
  IfFileExists "$PROGRAMFILES64\SafeExamBrowser\Application\SafeExamBrowser.exe" 0 +2
    StrCpy $SebPath "$PROGRAMFILES64\SafeExamBrowser\Application\SafeExamBrowser.exe"
  ${If} $SebPath == ""
    IfFileExists "$PROGRAMFILES64\SafeExamBrowser\SafeExamBrowser.exe" 0 +2
      StrCpy $SebPath "$PROGRAMFILES64\SafeExamBrowser\SafeExamBrowser.exe"
  ${EndIf}
  ${If} $SebPath == ""
    IfFileExists "$PROGRAMFILES32\SafeExamBrowser\Application\SafeExamBrowser.exe" 0 +2
      StrCpy $SebPath "$PROGRAMFILES32\SafeExamBrowser\Application\SafeExamBrowser.exe"
  ${EndIf}
  ${If} $SebPath != ""
    ${GetFileVersion} "$SebPath" $0
    ${VersionCompare} "$0" "3.10.2.920" $1
    ${If} $1 == 2
      StrCpy $SebPath ""
    ${EndIf}
  ${EndIf}
FunctionEnd

Function ReadDotNetRelease
  StrCpy $0 0
  SetRegView 64
  ClearErrors
  ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
  ${If} ${Errors}
    StrCpy $0 0
    SetRegView 32
    ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
  ${EndIf}
  SetRegView 64
FunctionEnd

Function CheckVendorResult
  ${If} $VendorResult == 3010
    SetRebootFlag true
    MessageBox MB_ICONINFORMATION "Компонент установлен. Перезагрузите Windows и снова откройте этот установщик. Экзамен автоматически не начнётся."
    SetErrorLevel 3010
    Abort
  ${ElseIf} $VendorResult != 0
    MessageBox MB_ICONSTOP "Установка компонента отменена или завершилась с ошибкой ($VendorResult). Roundlane не установлен."
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Section "Компоненты экзаменационного браузера"
  Call FindSEB
  ${If} $SebPath == ""
    InitPluginsDir
    SetOutPath "$PLUGINSDIR\Browser"
    File /oname=SafeExamBrowser-Setup.exe "../SEB_3.10.2.920_SetupBundle.exe"
    File "dependencies/vc_redist.x64.exe"
    File "dependencies/ndp48-x86-x64-allos-enu.exe"
    Call ReadDotNetRelease
    ${If} $0 < 528040
      DetailPrint "Установка Microsoft .NET Framework 4.8"
      ExecWait '"$PLUGINSDIR\Browser\ndp48-x86-x64-allos-enu.exe" /norestart' $VendorResult
      Call CheckVendorResult
      Call ReadDotNetRelease
      ${If} $0 < 528040
        MessageBox MB_ICONSTOP ".NET Framework 4.8 не найден после установки."
        Abort
      ${EndIf}
    ${EndIf}
    CreateDirectory "$LOCALAPPDATA\Roundlane\SetupLogs"
    DetailPrint "Установка Safe Exam Browser из комплекта Roundlane"
    ExecWait '"$PLUGINSDIR\Browser\SafeExamBrowser-Setup.exe" /install /norestart /log "$LOCALAPPDATA\Roundlane\SetupLogs\SEB-install.log"' $VendorResult
    Call CheckVendorResult
    Call FindSEB
    ${If} $SebPath == ""
      MessageBox MB_ICONSTOP "Экзаменационный браузер не установлен. Откройте установщик повторно."
      SetErrorLevel 1
      Abort
    ${EndIf}
  ${Else}
    DetailPrint "Экзаменационный браузер уже установлен"
  ${EndIf}
SectionEnd

Section "Roundlane"
  SetOutPath "$INSTDIR"
  File "dist/Roundlane.exe"
  File "dist/RoundlaneHub.exe"
  File "dist/contest.seb"
  File "dist/starter.cpp"
  File "dist/LICENSE-SEB.txt"
  File /oname=vendor-manifest.json "dependencies/manifest.json"
  SetOutPath "$INSTDIR\hub"
  File "dist/hub/index.html"
  File "dist/hub/app.js"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  SetShellVarContext current
  CreateDirectory "$SMPROGRAMS\Roundlane"
  CreateShortCut "$SMPROGRAMS\Roundlane\Roundlane.lnk" "$INSTDIR\Roundlane.exe"
  CreateShortCut "$SMPROGRAMS\Roundlane\Удалить Roundlane.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortCut "$DESKTOP\Roundlane.lnk" "$INSTDIR\Roundlane.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayName" "Roundlane"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayIcon" "$INSTDIR\Roundlane.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayVersion" "2.6"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "NoRepair" 1
SectionEnd

Function OpenOrganizer
  ExecShell "open" "$INSTDIR\Roundlane.exe"
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$DESKTOP\Roundlane.lnk"
  Delete "$SMPROGRAMS\Roundlane\Roundlane.lnk"
  Delete "$SMPROGRAMS\Roundlane\Удалить Roundlane.lnk"
  RMDir "$SMPROGRAMS\Roundlane"
  Delete "$INSTDIR\Roundlane.exe"
  Delete "$INSTDIR\RoundlaneHub.exe"
  Delete "$INSTDIR\contest.seb"
  Delete "$INSTDIR\starter.cpp"
  Delete "$INSTDIR\LICENSE-SEB.txt"
  Delete "$INSTDIR\vendor-manifest.json"
  Delete "$INSTDIR\hub\index.html"
  Delete "$INSTDIR\hub\app.js"
  RMDir "$INSTDIR\hub"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane"
SectionEnd
