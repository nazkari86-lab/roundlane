$ErrorActionPreference='Stop'
$out='C:\RoundlaneMemoryUpgrade'
if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Exam active'}
& 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:exe /platform:x64 /r:System.ServiceModel.dll "/out:$out\NativeRecoveryProxyProbe.exe" "$out\NativeRecoveryProxyProbe.cs" *> "$out\recovery-probe-compile.txt"
if($LASTEXITCODE){throw 'Probe compilation failed'}
& "$out\NativeRecoveryProxyProbe.exe" 'C:\RoundlaneHardenedRelease4\runtime' "$out\recovery-proxy-before.json" *> "$out\recovery-proxy-before.txt"
@{time=[DateTime]::UtcNow.ToString('o');exit=$LASTEXITCODE;examStarted=$false} | ConvertTo-Json | Set-Content "$out\recovery-proxy-before-exit.json"
