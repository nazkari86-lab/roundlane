param([string]$Root='C:\RoundlaneHardenedRelease2\runtime',[string]$Label='before')
$ErrorActionPreference='Stop'
$out='C:\RoundlaneMemoryUpgrade'
if($Label -notmatch '^(before|after)$'){throw 'Unknown test label'}
if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Exam active'}
& 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:exe /platform:x64 "/out:$out\NativeCommunicationProbe.exe" "$out\NativeCommunicationProbe.cs" *> "$out\communication-compile.txt"
if($LASTEXITCODE){throw 'Probe compilation failed'}
& "$out\NativeCommunicationProbe.exe" $Root "$out\communication-$Label.json" *> "$out\communication-$Label.txt"
@{exit=$LASTEXITCODE;root=$Root;finished=[DateTime]::UtcNow.ToString('o');examStarted=$false} | ConvertTo-Json | Set-Content "$out\communication-$Label-exit.json"
