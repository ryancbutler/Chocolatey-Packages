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

Export-ModuleMember -Function Get-NuspecVersion, Get-NuspecId, Set-NuspecVersion, Test-VersionIsNewer
