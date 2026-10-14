$ErrorActionPreference='Stop'
$out='C:\RoundlaneMemoryUpgrade'
if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Exam active'}
& 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:exe /platform:x64 "/out:$out\NativeMonitorProbe.exe" "$out\NativeMonitorProbe.cs" *> "$out\monitor-probe-compile.txt"
if($LASTEXITCODE){throw 'Probe compilation failed'}
$results=@()
foreach($case in @(@{label='before';root='C:\RoundlaneHardenedRelease3\runtime';expected=1},@{label='after';root='C:\RoundlaneHardenedRelease4\runtime';expected=0})){
 & "$out\NativeMonitorProbe.exe" $case.root "$out\monitor-probe-$($case.label).json" *> "$out\monitor-probe-$($case.label).txt"
 $results+=@{label=$case.label;exit=$LASTEXITCODE;expected=$case.expected;passed=($LASTEXITCODE -eq $case.expected)}
}
@{time=[DateTime]::UtcNow.ToString('o');results=$results;examStarted=$false} | ConvertTo-Json -Depth 5 | Set-Content "$out\monitor-probe-summary.json"
