import-module au

function global:au_BeforeUpdate {
    #$Latest.Checksum32 = Get-RemoteChecksum $Latest.URL32 
    #Get-RemoteFiles -Purge -NoSuffix 
}

function global:au_GetLatest {
    try {
        $download_page = Invoke-RestMethod -Uri "https://api.github.com/repos/EUCweb/BIS-F/releases/latest" -ErrorAction stop -SkipCertificateCheck -SkipHeaderValidation -MaximumRetryCount 3 -RetryIntervalSec 5
    }
    catch {
        return
    }
    write-host $version
    return @{
        Version = $download_page.tag_name
        URL32   = $download_page.assets.browser_download_url
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
