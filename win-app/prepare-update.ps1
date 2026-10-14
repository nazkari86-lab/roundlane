param([Parameter(Mandatory=$true)][string]$InstallDir)
$ErrorActionPreference='Stop'
try {
    if(Get-Process Roundlane.Runtime,Roundlane.Client -ErrorAction SilentlyContinue) {
        throw 'Finish the active Roundlane exam before updating.'
    }
    $root=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
    $runtime=Join-Path $root 'runtime'
    $service=Get-Service Roundlane -ErrorAction SilentlyContinue
    if($service -and $service.Status -ne 'Stopped') {
        Stop-Service Roundlane
        $service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
    }
    $backup=$null
    if(Test-Path -LiteralPath $runtime) {
        $item=Get-Item -LiteralPath $runtime
        if(!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'The existing runtime must be an ordinary directory.'
        }
        $name='previous-runtime-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
        $backup=Join-Path $root $name
        $counter=0
        while(Test-Path -LiteralPath $backup) {
            $counter++
            $backup=Join-Path $root ($name+'-'+$counter)
        }
        Move-Item -LiteralPath $runtime -Destination $backup
    }
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    @{prepared=$true;previousRuntime=$backup;time=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content (Join-Path $root 'last-update.json')
    exit 0
} catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    exit 1
}
