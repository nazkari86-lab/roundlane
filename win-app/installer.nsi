Unicode true
Name "Roundlane"
OutFile "dist/Roundlane 2.2 Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Roundlane"
RequestExecutionLevel user
SetCompressor /SOLID lzma
Icon "app.ico"
UninstallIcon "app.ico"

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File "dist/Roundlane.exe"
  File "dist/RoundlaneHub.exe"
  File "dist/contest.seb"
  File "dist/starter.cpp"
  SetOutPath "$INSTDIR\hub"
  File "dist/hub/index.html"
  File "dist/hub/app.js"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Roundlane"
  CreateShortCut "$SMPROGRAMS\Roundlane\Roundlane.lnk" "$INSTDIR\Roundlane.exe"
  CreateShortCut "$SMPROGRAMS\Roundlane\Удалить Roundlane.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortCut "$DESKTOP\Roundlane.lnk" "$INSTDIR\Roundlane.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayName" "Roundlane"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane" "DisplayVersion" "2.2"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\Roundlane.lnk"
  RMDir /r "$SMPROGRAMS\Roundlane"
  Delete "$INSTDIR\Roundlane.exe"
  Delete "$INSTDIR\RoundlaneHub.exe"
  Delete "$INSTDIR\contest.seb"
  Delete "$INSTDIR\starter.cpp"
  Delete "$INSTDIR\hub\index.html"
  Delete "$INSTDIR\hub\app.js"
  RMDir "$INSTDIR\hub"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Roundlane"
SectionEnd
