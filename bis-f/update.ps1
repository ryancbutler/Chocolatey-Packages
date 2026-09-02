[CmdletBinding()]
param()

$release = Get-GitHubLatestRelease -Repository 'EUCweb/BIS-F'

[pscustomobject]@{
    Version  = $release.Version
    Url      = $release.Url
    Checksum = Get-UrlChecksum -Url $release.Url
}
