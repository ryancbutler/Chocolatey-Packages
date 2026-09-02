[CmdletBinding()]
param(
    [string[]] $Name,
    [switch]   $Force,
    [switch]   $CheckOnly,
    [switch]   $NoPush,
    [switch]   $NoCommit,
    [string]   $Root = $PSScriptRoot
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$varsFile = Join-Path $PSScriptRoot 'update_vars.ps1'
if (Test-Path -LiteralPath $varsFile) { . $varsFile }

Import-Module (Join-Path $PSScriptRoot 'lib/ChocoPkg.psm1') -Force -Global
Import-Module (Join-Path $PSScriptRoot 'lib/Sources.psm1') -Force -Global

$artifactDirectory = Join-Path $Root 'artifacts'
$packages = @(Get-ChocoPackage -Root $Root)
if ($Name) { $packages = @($packages | Where-Object { $_.Name -in $Name }) }
if (-not $packages) { throw "No packages found to update (root '$Root', filter '$($Name -join ', ')')." }

$mode = if ($CheckOnly) { 'check only' } elseif ($NoPush) { 'no push' } else { 'full' }
Write-Host "Updating $($packages.Count) package(s), mode: $mode"
if ($Force) { Write-Host 'FORCE enabled: packages update even when the detected version is not newer.' }

$results = foreach ($package in $packages) {
    Write-Host ''
    Write-Host ('-' * 60)
    Write-Host "PACKAGE: $($package.Name)"

    $splat = @{
        Package           = $package
        ArtifactDirectory = $artifactDirectory
        Force             = $Force
        CheckOnly         = $CheckOnly
        NoPush            = $NoPush
    }
    $result = Invoke-PackageUpdate @splat

    Write-Host "  current:  $($result.CurrentVersion)"
    Write-Host "  detected: $($result.DetectedVersion)"
    Write-Host "  outcome:  $($result.Outcome)"
    if ($result.Error) { Write-Host "  error:    $($result.Error)" }
    $result
}

$results = @($results)
$committable = @($results | Where-Object { $_.Outcome -in @('pushed', 'already published', 'packed') -and $_.ChangedFiles })

if (-not $NoCommit -and -not $CheckOnly -and $committable) {
    # Stage only the files of packages that got as far as a successful pack/push.
    # A failed package has already had its files rewritten on disk; 'git add -A'
    # would record a version bump for something that was never published.
    $paths = $committable.ChangedFiles
    git add -- @paths
    if ($LASTEXITCODE -ne 0) { throw "git add failed with exit code $LASTEXITCODE" }

    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Nothing staged; skipping commit.'
    }
    else {
        $summary = ($committable | ForEach-Object { "$($_.Name) $($_.DetectedVersion)" }) -join ', '
        git commit -m "Update: $summary [skip ci]"
        if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE" }
        git push
        if ($LASTEXITCODE -ne 0) { throw "git push failed with exit code $LASTEXITCODE" }
    }
}

Write-Host ''
Write-Host ('=' * 60)
$results | Select-Object Name, CurrentVersion, DetectedVersion, Outcome | Format-Table -AutoSize | Out-String | Write-Host

$counts = $results | Group-Object Outcome | ForEach-Object { "$($_.Count) $($_.Name)" }
Write-Host ($counts -join ', ')

$failed = @($results | Where-Object { $_.Outcome -eq 'failed' })
if ($failed) {
    Write-Host ''
    Write-Host "FAILED: $($failed.Name -join ', ')"
    exit 1
}
exit 0
