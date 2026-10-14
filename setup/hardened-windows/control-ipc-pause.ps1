param([ValidateSet('compile','pause','resume')][string]$Action='compile')
$ErrorActionPreference='Stop'
$out='C:\RoundlaneMemoryUpgrade'
if($Action -eq 'compile'){
 if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Compile only outside an exam'}
 & 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:exe /platform:x64 "/out:$out\RuntimePauseProbe.exe" "$out\RuntimePauseProbe.cs" *> "$out\ipc-pause-compile.txt"
 if($LASTEXITCODE){throw 'Pause fixture compilation failed'}
 @{compiled=$true;time=[DateTime]::UtcNow.ToString('o');examStarted=$false} | ConvertTo-Json | Set-Content "$out\ipc-pause-compiled.json"
}elseif($Action -eq 'pause'){
 $clients=@(Get-Process Roundlane.Client -ErrorAction Stop)
 if($clients.Count -ne 1){throw 'Unexpected client count'}
 $log=Get-ChildItem C:\Users\roundlanetest\AppData\Local\Roundlane\Logs -Filter '*Client*' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
 if(!(Get-Content $log.FullName -Raw).Contains('contest access is suspended')){throw 'Quarantine must already be active'}
 $p=Start-Process "$out\RuntimePauseProbe.exe" -ArgumentList 'pause' -PassThru
 @{probePid=$p.Id;started=[DateTime]::UtcNow.ToString('o');automaticResumeSeconds=180} | ConvertTo-Json | Set-Content "$out\ipc-pause-start.json"
}else{
 & "$out\RuntimePauseProbe.exe" resume
 if($LASTEXITCODE){throw 'Manual resume failed'}
}
