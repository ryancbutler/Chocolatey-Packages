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

    @{
        "(?i)(^\s*url\s*=\s*)('.*')"      = "`${1}'$Url'"
        "(?i)(^\s*checksum\s*=\s*)('.*')" = "`${1}'$Checksum'"
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

Export-ModuleMember -Function Get-NuspecVersion, Get-NuspecId, Set-NuspecVersion, Test-VersionIsNewer, Get-DefaultReplacements, Update-PackageFile
