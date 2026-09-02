[CmdletBinding()]
param([string] $Path = "$PSScriptRoot/tests")

$ErrorActionPreference = 'Stop'

function Get-Pester5 {
    Get-Module Pester -ListAvailable |
        Where-Object { $_.Version -ge [version]'5.0.0' -and $_.Version -lt [version]'6.0.0' } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

$pester = Get-Pester5
if (-not $pester) {
    Write-Host 'Pester 5 not found; installing to CurrentUser...'
    Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck
    $pester = Get-Pester5
}
if (-not $pester) { throw 'Pester 5 could not be installed.' }

Import-Module $pester.Path -Force
Write-Host "Using Pester $($pester.Version)"

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
