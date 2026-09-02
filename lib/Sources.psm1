Set-StrictMode -Version 3.0

function Select-FsLogixReleaseFromHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Html)

    $anchors = [regex]::Matches(
        $Html,
        '<a\b[^>]*>.*?</a>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $found = foreach ($anchor in $anchors) {
        $tag = $anchor.Value
        if ($tag -notmatch 'data-linktype\s*=\s*"external"') { continue }

        if ($tag -notmatch '\((\d+(?:\.\d+){1,3})\)') { continue }
        $versionText = $Matches[1]

        if ($tag -notmatch 'href\s*=\s*"([^"]+)"') { continue }
        $url = $Matches[1]

        $parsed = $null
        if (-not [version]::TryParse($versionText, [ref]$parsed)) { continue }

        [pscustomobject]@{ Version = $versionText; Url = $url; Sort = $parsed }
    }

    if (-not $found) { throw 'Found no external link with a parseable version on the FSLogix release notes page.' }

    $best = $found | Sort-Object Sort -Descending | Select-Object -First 1
    [pscustomobject]@{ Version = $best.Version; Url = $best.Url }
}

function Get-FsLogixRelease {
    [CmdletBinding()]
    param([string] $Uri = 'https://learn.microsoft.com/en-us/fslogix/overview-release-notes')

    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -MaximumRetryCount 3 -RetryIntervalSec 5
    Select-FsLogixReleaseFromHtml -Html $response.Content
}

function Select-MsiAssetFromRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Release)

    $msi = $Release.assets | Where-Object { $_.browser_download_url -match '\.msi$' } | Select-Object -First 1
    if (-not $msi) { throw 'GitHub latest release does not contain an MSI asset.' }

    [pscustomobject]@{
        Version = ([string]$Release.tag_name).TrimStart('v')
        Url     = $msi.browser_download_url
    }
}

function Get-GitHubLatestRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Repository)

    $headers = @{
        'User-Agent' = 'chocolatey-package-update'
        'Accept'     = 'application/vnd.github+json'
    }
    # Runner IPs are shared and heavily rate-limited unauthenticated.
    if ($env:github_api_key) { $headers['Authorization'] = "Bearer $($env:github_api_key)" }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" `
        -Headers $headers -MaximumRetryCount 3 -RetryIntervalSec 5
    Select-MsiAssetFromRelease -Release $release
}

Export-ModuleMember -Function Select-FsLogixReleaseFromHtml, Get-FsLogixRelease, Select-MsiAssetFromRelease, Get-GitHubLatestRelease
