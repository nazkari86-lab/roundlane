$out='C:\RoundlaneMemoryUpgrade'
$state=if(Test-Path "$out\recovery-native-state.json"){Get-Content "$out\recovery-native-state.json" -Raw | ConvertFrom-Json}else{$null}
$live=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -in @('MSBuild.exe','csc.exe','Roundlane.Runtime.exe','Roundlane.Client.exe')} | Select-Object Name,ProcessId,CreationDate,CommandLine)
@{time=[DateTime]::UtcNow.ToString('o');state=$state;live=$live} | ConvertTo-Json -Depth 6 | Set-Content "$out\recovery-build-live.json"
