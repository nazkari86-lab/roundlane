$ErrorActionPreference='Stop'
$source='C:\RoundlaneSource\upstream\seb-win-refactoring'
$out='C:\RoundlaneMemoryUpgrade'
if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Exam active'}
if(@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'MSBuild.exe' -and $_.CommandLine -notmatch '/nodemode:1'}).Count){throw 'Build active'}
$rows=Get-Content "$out\recovery-source.json" -Raw | ConvertFrom-Json
if($rows.Count -ne 4){throw 'Unexpected patch inventory'}
foreach($row in $rows){if((Get-FileHash (Join-Path $source $row.path)).Hash.ToLowerInvariant() -ne $row.before){throw "Baseline mismatch: $($row.path)"}}
$backup=Join-Path $out ('recovery-backup-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))
New-Item -ItemType Directory $backup | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead("$out\recovery-source.zip")
try{
 if($zip.Entries.Count -ne 4){throw 'Wrong ZIP inventory'}
 foreach($row in $rows){
  $entry=$zip.GetEntry($row.path);if(!$entry){throw 'Missing patch member'}
  $target=Join-Path $source $row.path
  Copy-Item $target (Join-Path $backup ($row.path.Replace('/','_')))
  [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
  if((Get-FileHash $target).Hash.ToLowerInvariant() -ne $row.after){throw 'Patched source mismatch'}
 }
}finally{$zip.Dispose()}
$msbuild='C:\RoundlaneBuildTools\MSBuild\Current\Bin\MSBuild.exe'
$env:NUGET_PACKAGES='C:\RoundlaneNuget'
@{state='building';time=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content "$out\recovery-native-state.json"
foreach($project in @('Service','ResetUtility','Client','Runtime')){
 & $msbuild "$source\SafeExamBrowser.$project\SafeExamBrowser.$project.csproj" /t:Rebuild /m:2 /nodeReuse:false /p:Configuration=Release /p:Platform=x64 /p:Deterministic=true "/p:SolutionDir=$source\" /verbosity:minimal /nologo *> "$out\recovery-build-$project.txt"
 if($LASTEXITCODE){@{state='failed';project=$project;exit=$LASTEXITCODE;time=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content "$out\recovery-native-state.json";throw 'Build failed'}
}
@{state='passed';time=[DateTime]::UtcNow.ToString('o');examStarted=$false;needsSignature=$true} | ConvertTo-Json | Set-Content "$out\recovery-native-state.json"
