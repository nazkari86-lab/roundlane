$ErrorActionPreference='Stop'
$source='C:\RoundlaneSource\upstream\seb-win-refactoring'
$out='C:\RoundlaneMemoryUpgrade'
$stage='C:\RoundlaneHardenedRelease5'
$root="$stage\runtime"
$build=Get-Content "$out\recovery-native-completed.json" -Raw | ConvertFrom-Json
if($build.state -ne 'passed'){throw 'Latest build not verified'}
if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue){throw 'Exam process is active'}
if(Get-Process MSBuild -ErrorAction SilentlyContinue){throw 'Build still active; do not stage mutable output'}
if(Test-Path $stage){throw 'Preserve existing stage; use a new reviewed directory'}
New-Item -ItemType Directory -Force $root | Out-Null
foreach($project in @('Runtime','Client','Service','ResetUtility')){
 $from="$source\SafeExamBrowser.$project\bin\x64\Release"
 Get-ChildItem $from -File -Recurse | Where-Object {$_.Extension -ne '.pdb' -and $_.Name -notin @('manifest.json','manifest.sig') -and ($_.Extension -ne '.xml' -or $_.Name -eq 'ThirdPartyNotices.xml')} | ForEach-Object {
  $relative=$_.FullName.Substring($from.Length+1)
  $dest=Join-Path $root $relative
  if(Test-Path $dest){
   if((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $dest).Hash){throw "Conflicting built output: $relative"}
   # A prior release may share the underlying file. Never overwrite a link.
   return
  }
  New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
  $prior=Join-Path 'C:\RoundlaneHardenedRelease4\runtime' $relative
  if(!(Test-Path $dest) -and (Test-Path $prior) -and (Get-FileHash $prior).Hash -eq (Get-FileHash $_.FullName).Hash){
   New-Item -ItemType HardLink -Path $dest -Target $prior | Out-Null
  }else{Copy-Item $_.FullName $dest}
 }
}
foreach($file in @('Roundlane.Runtime.exe','Roundlane.Client.exe','Roundlane.Service.exe','Roundlane.Recovery.exe','SafeExamBrowser.Configuration.dll','SafeExamBrowser.UserInterface.Desktop.dll','libcef.dll','CefSharp.Core.Runtime.dll')){
 if(!(Test-Path "$root\$file")){throw "Missing release component: $file"}
}
Copy-Item "$source\LICENSE.txt","$source\ROUNDLANE-NOTICE.txt" $root
$notices="$root\ThirdPartyNotices"
foreach($packageRoot in @("$source\packages",'C:\RoundlaneNuget')){
 if(Test-Path $packageRoot){
  Get-ChildItem $packageRoot -File -Recurse | Where-Object {$_.Name -match '^(license|licence|copying|notice)' -or $_.Extension -eq '.nuspec'} | ForEach-Object {
   $relative=$_.FullName.Substring($packageRoot.Length+1)
   $dest=Join-Path $notices $relative
   New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
   $prior=Join-Path 'C:\RoundlaneHardenedRelease4\runtime' $relative
  if(!(Test-Path $dest) -and (Test-Path $prior) -and (Get-FileHash $prior).Hash -eq (Get-FileHash $_.FullName).Hash){
   New-Item -ItemType HardLink -Path $dest -Target $prior | Out-Null
  }else{Copy-Item $_.FullName $dest -Force}
  }
 }
}
$files=Get-ChildItem $root -File -Recurse | ForEach-Object {@{path=$_.FullName.Substring($root.Length+1).Replace('\','/');sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}
@{version='3.0';upstream='167f82f8c3ec6773ec9be6c5af7fb492b5b2ed50';files=@($files)} | ConvertTo-Json -Depth 5 | Set-Content "$root\manifest.json" -Encoding UTF8
Copy-Item "$root\manifest.json" "$out\recovery-release-manifest.json"
@{stage=$root;status='pending-host-signature';files=@($files).Count;bytes=(Get-ChildItem $root -File -Recurse | Measure-Object Length -Sum).Sum;build=$build;created=[DateTime]::UtcNow.ToString('o');examStarted=$false} | ConvertTo-Json -Depth 5 | Set-Content "$out\recovery-release-stage.json"
