$ErrorActionPreference='Stop'
try {
Set-Content 'C:\RoundlaneMemoryUpgrade\initiating-recovery-wcf-started.txt' ([DateTime]::UtcNow.ToString('o'))
$ErrorActionPreference='Stop'
$out='C:\RoundlaneMemoryUpgrade'
$build=Get-Content "$out\initiating-recovery-native-completed.json" -Raw | ConvertFrom-Json
if($build.state -ne 'passed' -or (Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue)){throw 'Build unfinished or exam active'}
$root='C:\RoundlaneSource\upstream\seb-win-refactoring\SafeExamBrowser.Runtime\bin\x64\Release'
$refs=@('SafeExamBrowser.Communication.dll','SafeExamBrowser.Communication.Contracts.dll','SafeExamBrowser.Logging.dll','SafeExamBrowser.Logging.Contracts.dll') | ForEach-Object {"/r:$root\$_"}
& 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:exe /platform:x64 /r:System.ServiceModel.dll @refs "/out:$root\NativeWcfRecoveryProbe.exe" "$out\NativeWcfRecoveryProbe.cs" *> "$out\initiating-recovery-wcf-compile.txt"
if($LASTEXITCODE){throw 'Real WCF probe compilation failed'}
$ErrorActionPreference='Continue'
& "$root\NativeWcfRecoveryProbe.exe" $root "$out\initiating-recovery-wcf.json" 2>&1 | Out-File "$out\initiating-recovery-wcf.txt"
$result=$LASTEXITCODE
$ErrorActionPreference='Stop'
Remove-Item "$root\NativeWcfRecoveryProbe.exe" -Force
@{time=[DateTime]::UtcNow.ToString('o');exit=$result;examStarted=$false} | ConvertTo-Json | Set-Content "$out\initiating-recovery-wcf-exit.json"
if($result){throw 'Real WCF recovery checks failed'}

} catch {
@{time=[DateTime]::UtcNow.ToString('o');message=$_.Exception.Message;scriptStack=$_.ScriptStackTrace;detail=($_ | Out-String)} | ConvertTo-Json -Depth 4 | Set-Content 'C:\RoundlaneMemoryUpgrade\initiating-recovery-wcf-error.json'
}
