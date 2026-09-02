[CmdletBinding()]
param()

$release = Get-FsLogixRelease

# The Microsoft download host needs these; without them the request is rejected.
$webRequestArgs = @{
    SkipCertificateCheck = $true
    SkipHeaderValidation = $true
}

[pscustomobject]@{
    Version  = $release.Version
    Url      = $release.Url
    Checksum = Get-UrlChecksum -Url $release.Url -WebRequestArgs $webRequestArgs
}
