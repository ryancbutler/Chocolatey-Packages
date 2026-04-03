if ($PSVersionTable.PSEdition -eq 'Core') {
    $winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $winPs)) {
        throw 'Windows PowerShell 5.1 is required for this AU script, but powershell.exe was not found.'
    }

    & $winPs -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

import-module au

function global:au_BeforeUpdate {
    #$Latest.Checksum32 = Get-RemoteChecksum $Latest.URL32 
    #Get-RemoteFiles -Purge -NoSuffix 
}

function global:au_GetLatest {
    try {
        $headers = @{
            'User-Agent' = 'chocolatey-au-update-script'
            'Accept'     = 'application/vnd.github+json'
        }
        $downloadPage = Invoke-RestMethod -Uri 'https://api.github.com/repos/EUCweb/BIS-F/releases/latest' -Headers $headers -ErrorAction Stop
    }
    catch {
        throw "Unable to fetch latest BIS-F release metadata from GitHub. $($_.Exception.Message)"
    }

    $msiAsset = $downloadPage.assets | Where-Object { $_.browser_download_url -match '\.msi$' } | Select-Object -First 1
    if (-not $msiAsset) {
        throw 'GitHub latest release does not contain an MSI asset.'
    }

    $version = [string]$downloadPage.tag_name
    $version = $version.TrimStart('v')

    return @{
        Version = $version
        URL32   = $msiAsset.browser_download_url
    }
}

function global:au_SearchReplace {
    @{
        "tools\chocolateyInstall.ps1" = @{
            "(?i)(^\s*url\s*=\s*)('.*')"      = "`$1'$($Latest.URL32)'"
            "(?i)(^\s*checksum\s*=\s*)('.*')" = "`$1'$($Latest.Checksum32)'"
        }
    }
}

update
