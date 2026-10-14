$ErrorActionPreference='Stop'
$source='C:\RoundlaneSource\upstream\seb-win-refactoring'
$out='C:\RoundlaneMemoryUpgrade'
$report="$out\initiating-recovery-native-completed.json"
$project=$null
try {
 if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Exam active'}
 if(Get-Process MSBuild -ErrorAction SilentlyContinue){throw 'Build active'}
 $rows=Get-Content "$out\initiating-recovery-source.json" -Raw | ConvertFrom-Json
 if($rows.Count -ne 7){throw 'Unexpected source inventory'}
 foreach($row in $rows){
  if((Get-FileHash (Join-Path $source $row.path)).Hash.ToLowerInvariant() -ne $row.after){throw "Patched source mismatch: $($row.path)"}
 }
 $msbuild='C:\RoundlaneBuildTools\MSBuild\Current\Bin\MSBuild.exe'
 $env:NUGET_PACKAGES='C:\RoundlaneNuget'
 $started=[DateTime]::UtcNow.ToString('o')
 foreach($project in @('Service','ResetUtility','Client','Runtime')){
  # Each progress file is immutable once published. Readers must not hold the
  # final report open while the build orchestrator is still writing it.
  @{state='building';project=$project;time=[DateTime]::UtcNow.ToString('o');started=$started;pid=$PID} | ConvertTo-Json | Set-Content "$out\initiating-recovery-finish-start-$project.json"
  & $msbuild "$source\SafeExamBrowser.$project\SafeExamBrowser.$project.csproj" /t:Build /m:1 /nodeReuse:false /p:Configuration=Release /p:Platform=x64 /p:Deterministic=true "/p:SolutionDir=$source\" /verbosity:minimal /nologo *> "$out\initiating-recovery-finish-$project.txt"
  $code=$LASTEXITCODE
  if($code){throw "Build failed: $project exit $code"}
 }
 @{state='passed';time=[DateTime]::UtcNow.ToString('o');started=$started;examStarted=$false;needsSignature=$true;projects=@('Service','ResetUtility','Client','Runtime');sourceHashesVerified=$true;buildTarget='Build'} | ConvertTo-Json | Set-Content $report
} catch {
 @{state='failed';project=$project;time=[DateTime]::UtcNow.ToString('o');error=$_.Exception.Message;examStarted=$false} | ConvertTo-Json | Set-Content "$out\initiating-recovery-finish-error-final.json"
 throw
}
