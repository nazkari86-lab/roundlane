$ErrorActionPreference='Stop'
$out='C:\RoundlaneMemoryUpgrade'
$build=Get-Content "$out\recovery-native-completed.json" -Raw | ConvertFrom-Json
if($build.state -ne 'passed' -or (Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue)){throw 'Build unfinished or exam active'}
$root='C:\RoundlaneHardenedRelease5\runtime'
& 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:exe /platform:x64 /r:System.ServiceModel.dll "/out:$out\NativeRecoveryProxyProbe.exe" "$out\NativeRecoveryProxyProbe.cs" *> "$out\recovery-probe-after-compile.txt"
if($LASTEXITCODE){throw 'Recovery probe compilation failed'}
& "$out\NativeRecoveryProxyProbe.exe" $root "$out\recovery-proxy-after.json" *> "$out\recovery-proxy-after.txt"
$result=$LASTEXITCODE
@{time=[DateTime]::UtcNow.ToString('o');exit=$result;examStarted=$false} | ConvertTo-Json | Set-Content "$out\recovery-proxy-after-exit.json"
if($result){throw 'Recovery proxy checks failed'}
& "$out\NativeMonitorProbe.exe" $root "$out\recovery-monitor-after.json" *> "$out\recovery-monitor-after.txt"
if($LASTEXITCODE){throw 'Monitor regression failed'}
@{passed=$true;time=[DateTime]::UtcNow.ToString('o');examStarted=$false} | ConvertTo-Json | Set-Content "$out\recovery-native-probes.json"
