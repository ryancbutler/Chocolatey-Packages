Set-StrictMode -Version 3.0

function Get-NuspecXml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($resolved)
    $xml
}

function Get-NuspecVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $xml = Get-NuspecXml -Path $Path
    $node = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="version"]')
    if (-not $node) { throw "No <version> element found in '$Path'." }
    $node.InnerText
}

function Get-NuspecId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $xml = Get-NuspecXml -Path $Path
    $node = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="id"]')
    if (-not $node) { throw "No <id> element found in '$Path'." }
    $node.InnerText
}

function Set-NuspecVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Version
    )

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $xml = Get-NuspecXml -Path $resolved
    $node = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="version"]')
    if (-not $node) { throw "No <version> element found in '$resolved'." }
    $node.InnerText = $Version

    # XmlDocument.Save(string) writes a BOM; the nuspec files have none, so write
    # through an explicit writer to keep the file byte-identical apart from the version.
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $false
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::None
    $writer = [System.Xml.XmlWriter]::Create($resolved, $settings)
    try { $xml.Save($writer) } finally { $writer.Dispose() }
}

function Test-VersionIsNewer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Candidate,
        [Parameter(Mandatory)][string] $Current
    )

    $c = $null
    $u = $null
    if (-not [version]::TryParse($Candidate, [ref]$c)) { throw "Unparseable candidate version: '$Candidate'" }
    if (-not [version]::TryParse($Current, [ref]$u))   { throw "Unparseable current version: '$Current'" }
    $c -gt $u
}

function Get-DefaultReplacements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Url,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Checksum
    )

    $escapedUrl = $Url.Replace('$', '$$')
    $escapedChecksum = $Checksum.Replace('$', '$$')

    @{
        "(?i)(^\s*url\s*=\s*)('[^']*')"      = "`${1}'$escapedUrl'"
        "(?i)(^\s*checksum\s*=\s*)('[^']*')" = "`${1}'$escapedChecksum'"
    }
}

function Update-PackageFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][hashtable] $Replacements
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: '$Path'" }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath

    $bytes = [System.IO.File]::ReadAllBytes($resolved)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [System.IO.File]::ReadAllText($resolved)

    foreach ($pattern in $Replacements.Keys) {
        $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if (-not $regex.IsMatch($text)) {
            throw "Pattern matched nothing in '$resolved': $pattern"
        }
        $text = $regex.Replace($text, $Replacements[$pattern])
    }

    $encoding = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($resolved, $text, $encoding)
}

$script:ChecksumCache = @{}

# Package update scripts run as external .ps1 files invoked (directly or via
# Invoke-WithRetry's scriptblock) from Invoke-PackageUpdate. Invoking an external
# script inserts a new "script"-scope into the dynamic scope chain, so a plain
# `$script:ChecksumCache` reference inside this function - called back into from
# such a script - resolves against *that script's* empty scope, not this module's,
# and throws under Set-StrictMode. Going through this module's own SessionState
# explicitly sidesteps that: it is the same single hashtable for the life of the
# process regardless of how many external-script scopes sit between the caller
# and here, which is what keeps the fslogix/fslogix-rule cross-package cache
# dedupe (both packages hash the same upstream zip) working correctly.
function Clear-UrlChecksumCache {
    [CmdletBinding()]
    param()
    $MyInvocation.MyCommand.Module.SessionState.PSVariable.Set('ChecksumCache', @{})
}

function Get-UrlChecksum {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Url,
        [hashtable] $WebRequestArgs = @{}
    )

    $cache = $MyInvocation.MyCommand.Module.SessionState.PSVariable.GetValue('ChecksumCache')
    if ($cache.ContainsKey($Url)) { return $cache[$Url] }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    try {
        Invoke-WebRequest -Uri $Url -OutFile $temp -MaximumRetryCount 3 -RetryIntervalSec 5 @WebRequestArgs
        $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    $cache[$Url] = $hash
    $hash
}

function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [int] $Attempts = 3,
        [int] $DelaySeconds = 15
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try { return & $ScriptBlock }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Host "  attempt $i of $Attempts failed: $($_.Exception.Message)"
            if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
        }
    }
}

function Invoke-ChocoPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $NuspecPath,
        [Parameter(Mandatory)][string] $OutputDirectory
    )

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $resolvedNuspec = (Resolve-Path -LiteralPath $NuspecPath).ProviderPath
    $resolvedOut = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath

    $packArgs = @('pack', $resolvedNuspec, '--output-directory', $resolvedOut, '--limit-output')
    & choco @packArgs
    if ($LASTEXITCODE -ne 0) { throw "choco pack failed with exit code $LASTEXITCODE" }

    $id = Get-NuspecId -Path $resolvedNuspec
    $version = Get-NuspecVersion -Path $resolvedNuspec
    $expected = Join-Path $resolvedOut "$id.$version.nupkg"
    if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) {
        throw "choco pack reported success but '$expected' does not exist."
    }
    $expected
}

function Get-ChocoPushArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $NupkgPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Source,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ApiKey
    )

    foreach ($pair in @(@('NupkgPath', $NupkgPath), @('Source', $Source), @('ApiKey', $ApiKey))) {
        if ([string]::IsNullOrWhiteSpace($pair[1])) { throw "$($pair[0]) must not be empty." }
    }

    @('push', $NupkgPath, '--source', $Source, '--api-key', $ApiKey, '--limit-output')
}

function Test-DuplicateVersionOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Output)

    [bool]($Output -match '(?i)already exists|\(409\)')
}

function Invoke-ChocoPush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $NupkgPath,
        [string] $Source = 'https://push.chocolatey.org',
        [string] $ApiKey = $env:api_key
    )

    $pushArgs = Get-ChocoPushArgs -NupkgPath $NupkgPath -Source $Source -ApiKey $ApiKey
    $raw = (& choco @pushArgs 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $safe = $raw.Replace($ApiKey, '***')

    $outcome =
        if ($code -eq 0) { 'pushed' }
        elseif (Test-DuplicateVersionOutput -Output $safe) { 'already published' }
        else { 'failed' }

    [pscustomobject]@{ Outcome = $outcome; Output = $safe }
}

function Get-ChocoPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root)

    Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
        $updateScript = Join-Path $_.FullName 'update.ps1'
        $nuspec = Get-ChildItem -LiteralPath $_.FullName -Filter '*.nuspec' -File | Select-Object -First 1
        if ((Test-Path -LiteralPath $updateScript -PathType Leaf) -and $nuspec) {
            [pscustomobject]@{
                Name         = $_.Name
                Path         = $_.FullName
                NuspecPath   = $nuspec.FullName
                UpdateScript = $updateScript
            }
        }
    } | Sort-Object Name
}

function Get-OptionalProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string] $Name,
        $Default = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value) { $property.Value } else { $Default }
}

function Invoke-PackageUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Package,
        [Parameter(Mandatory)][string] $ArtifactDirectory,
        [string] $Source = 'https://push.chocolatey.org',
        [string] $ApiKey = $env:api_key,
        [int]    $DetectAttempts = 3,
        [int]    $DetectDelaySeconds = 15,
        [switch] $Force,
        [switch] $CheckOnly,
        [switch] $NoPush
    )

    $result = [pscustomobject]@{
        Name            = $Package.Name
        CurrentVersion  = $null
        DetectedVersion = $null
        Outcome         = 'failed'
        Failed          = $true
        ChangedFiles    = @()
        Error           = $null
        Output          = ''
    }

    try {
        $result.CurrentVersion = Get-NuspecVersion -Path $Package.NuspecPath

        $detected = Invoke-WithRetry -ScriptBlock { & $Package.UpdateScript } -Attempts $DetectAttempts -DelaySeconds $DetectDelaySeconds | Select-Object -Last 1
        if (-not $detected) { throw "'$($Package.Name)' update script returned nothing." }

        foreach ($required in @('Version', 'Url', 'Checksum')) {
            if ([string]::IsNullOrWhiteSpace((Get-OptionalProperty -InputObject $detected -Name $required))) {
                throw "'$($Package.Name)' update script did not return a non-empty '$required'."
            }
        }
        $result.DetectedVersion = $detected.Version

        if (-not $Force -and -not (Test-VersionIsNewer -Candidate $detected.Version -Current $result.CurrentVersion)) {
            $result.Outcome = 'no change'
            $result.Failed = $false
            return $result
        }

        if ($CheckOnly) {
            $result.Outcome = 'checked'
            $result.Failed = $false
            return $result
        }

        $installRelative = Get-OptionalProperty -InputObject $detected -Name 'InstallScript' -Default 'tools\chocolateyinstall.ps1'
        $installPath = Join-Path $Package.Path $installRelative
        $replacements = Get-OptionalProperty -InputObject $detected -Name 'Replace' `
            -Default (Get-DefaultReplacements -Url $detected.Url -Checksum $detected.Checksum)

        Update-PackageFile -Path $installPath -Replacements $replacements
        Set-NuspecVersion -Path $Package.NuspecPath -Version $detected.Version
        $result.ChangedFiles = @(
            (Resolve-Path -LiteralPath $installPath).ProviderPath
            (Resolve-Path -LiteralPath $Package.NuspecPath).ProviderPath
        )

        $nupkg = Invoke-ChocoPack -NuspecPath $Package.NuspecPath -OutputDirectory $ArtifactDirectory

        if ($NoPush) {
            $result.Outcome = 'packed'
            $result.Failed = $false
            return $result
        }

        $push = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $push = Invoke-ChocoPush -NupkgPath $nupkg -Source $Source -ApiKey $ApiKey
            if ($push.Outcome -ne 'failed') { break }
            if ($attempt -lt 3) {
                Write-Host "  push attempt $attempt failed; retrying"
                Start-Sleep -Seconds 15
            }
        }

        $result.Outcome = $push.Outcome
        $result.Output = $push.Output
        if ($push.Outcome -eq 'failed') {
            $result.Failed = $true
            $result.Error = "choco push failed: $($push.Output)"
            $result.ChangedFiles = @()
        }
        else {
            $result.Failed = $false
        }
    }
    catch {
        $result.Outcome = 'failed'
        $result.Failed = $true
        $result.Error = $_
        $result.ChangedFiles = @()
    }

    $result
}

Export-ModuleMember -Function Get-NuspecVersion, Get-NuspecId, Set-NuspecVersion, Test-VersionIsNewer, Get-DefaultReplacements, Update-PackageFile, Get-UrlChecksum, Clear-UrlChecksumCache, Invoke-WithRetry, Invoke-ChocoPack, Get-ChocoPushArgs, Test-DuplicateVersionOutput, Invoke-ChocoPush, Get-ChocoPackage, Get-OptionalProperty, Invoke-PackageUpdate
