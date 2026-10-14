param([string]$Source = 'C:\RoundlaneSource\upstream\seb-win-refactoring', [string]$Output = 'C:\RoundlaneNative')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Keep packages outside System32: x86/ARM64 process redirection in a guest
# otherwise makes Roslyn and MSBuild see different systemprofile directories.
$env:NUGET_PACKAGES = Join-Path (Split-Path $Output -Parent) 'RoundlaneNuget'
$msbuild = 'C:\RoundlaneBuildTools\MSBuild\Current\Bin\MSBuild.exe'
if (!(Test-Path $msbuild)) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (!(Test-Path $vswhere)) { throw 'Visual Studio Build Tools with .NET Framework 4.8/WPF are required.' }
    $msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
}
if (!$msbuild -or !(Test-Path $msbuild)) { throw 'MSBuild not found' }
New-Item -ItemType Directory -Force $Output | Out-Null
$nuget = Join-Path (Split-Path $Source -Parent) 'nuget.exe'
if (!(Test-Path $nuget)) { Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nuget -UseBasicParsing }
Push-Location $Source
try {
    # Restore packages directly: the upstream solution also contains a WiX setup
    # project, which is not used by Roundlane's own installer.
    $restoreDir = Join-Path $Output 'restore'
    New-Item -ItemType Directory -Force $restoreDir | Out-Null
    $packages = @{}
    Get-ChildItem $Source -Filter packages.config -Recurse | Where-Object { $_.FullName -notmatch '\\packages\\' } | ForEach-Object {
        [xml]$config = Get-Content $_.FullName
        foreach ($package in $config.packages.package) { $packages["$($package.id)/$($package.version)"] = $package.OuterXml }
    }
    '<packages>' + (($packages.Keys | Sort-Object | ForEach-Object { $packages[$_] }) -join "`n") + '</packages>' | Set-Content (Join-Path $restoreDir 'packages.config')
    & $nuget restore (Join-Path $restoreDir 'packages.config') -PackagesDirectory (Join-Path $Source 'packages') -NonInteractive -Verbosity quiet *> (Join-Path $Output 'restore.log')
    if ($LASTEXITCODE) { throw "NuGet restore failed: $LASTEXITCODE" }
    foreach ($project in @('Runtime', 'Client', 'Service', 'ResetUtility')) {
        & $msbuild "SafeExamBrowser.$project\SafeExamBrowser.$project.csproj" /restore /t:Rebuild /m:2 /nodeReuse:false /p:RestorePackagesConfig=true /p:Configuration=Release /p:Platform=x64 /p:Deterministic=true "/p:SolutionDir=$Source\" /verbosity:minimal /nologo *> (Join-Path $Output "build-$project.log")
        if ($LASTEXITCODE) { throw "Build $project failed: $LASTEXITCODE" }
    }
    # Verify shared dependencies before merging; never silently overwrite a
    # different build of the same assembly or reuse an old signed inventory.
    $assemblyHashes = @{}
    foreach ($project in @('Runtime', 'Client', 'Service', 'ResetUtility')) {
        Get-ChildItem "SafeExamBrowser.$project\bin\x64\Release" -Filter *.dll -File | ForEach-Object {
            $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
            if ($assemblyHashes.ContainsKey($_.Name) -and $assemblyHashes[$_.Name] -ne $hash) {
                throw "Conflicting native assembly: $($_.Name)"
            }
            $assemblyHashes[$_.Name] = $hash
        }
    }
    $runtime = Join-Path $Output ('runtime-staging-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $runtime | Out-Null
    Copy-Item 'SafeExamBrowser.Runtime\bin\x64\Release\*' $runtime -Recurse -Force
    Copy-Item 'SafeExamBrowser.Client\bin\x64\Release\*' $runtime -Recurse -Force
    Copy-Item 'SafeExamBrowser.Service\bin\x64\Release\*' $runtime -Recurse -Force
    Copy-Item 'SafeExamBrowser.ResetUtility\bin\x64\Release\*' $runtime -Recurse -Force
    Copy-Item LICENSE.txt,ROUNDLANE-NOTICE.txt $runtime
    $licenses = Join-Path $runtime 'ThirdPartyNotices'
    New-Item -ItemType Directory -Force $licenses | Out-Null
    foreach ($packageRoot in @((Join-Path $Source 'packages'), $env:NUGET_PACKAGES)) {
        Get-ChildItem $packageRoot -File -Recurse | Where-Object { $_.Name -match '^(license|licence|copying|notice)' -or $_.Extension -eq '.nuspec' } | ForEach-Object {
            $relative = $_.FullName.Substring($packageRoot.Length+1)
            $destination = Join-Path $licenses $relative
            New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
            Copy-Item $_.FullName $destination -Force
        }
    }
    foreach ($file in @('Roundlane.Runtime.exe','Roundlane.Client.exe','Roundlane.Service.exe','Roundlane.Recovery.exe','CefSharp.Core.Runtime.dll','libcef.dll')) {
        if (!(Test-Path (Join-Path $runtime $file))) { throw "Missing runtime component: $file" }
    }
    if (Test-Path (Join-Path $runtime 'SafeExamBrowser.exe')) { throw 'External SEB executable must not be included' }
    $manifest = Get-ChildItem $runtime -File -Recurse | Where-Object { $_.Name -notin @('manifest.json', 'manifest.sig') } | ForEach-Object {
        @{path=$_.FullName.Substring($runtime.Length + 1).Replace('\','/'); sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    @{version='3.0'; upstream='167f82f8c3ec6773ec9be6c5af7fb492b5b2ed50'; files=@($manifest)} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $runtime 'manifest.json') -Encoding UTF8
    $publishedRuntime = Join-Path $Output 'runtime'
    if (Test-Path $publishedRuntime) {
        Move-Item $publishedRuntime (Join-Path $Output ('runtime-previous-' + [Guid]::NewGuid().ToString('N')))
    }
    Move-Item $runtime $publishedRuntime
    $runtime = $publishedRuntime
    Compress-Archive -Path $runtime -DestinationPath (Join-Path $Output 'Roundlane-native-runtime.zip') -Force
    @{build='passed'; independentRuntime=$true; proprietaryIntegrityModule=$false; protectedExamVerified=$false; finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $Output 'result.json')
} catch {
    @{build='failed'; error=$_.Exception.Message; finished=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $Output 'result.json')
    throw
} finally { Pop-Location }
