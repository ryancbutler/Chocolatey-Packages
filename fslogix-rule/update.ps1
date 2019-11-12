import-module au
$url = "https://aka.ms/fslogix_download"

function global:au_BeforeUpdate {
    mkdir temp -Force
    Invoke-WebRequest -Uri $url -UseBasicParsing -outfile "temp\fslogix.zip" -Verbose
    $Latest.checksum_zip = Get-FileHash temp\fslogix.zip | ForEach-Object Hash

}

function global:au_GetLatest {
    $uri = Invoke-WebRequest -MaximumRedirection 0 -Uri $url -ErrorAction SilentlyContinue -UseBasicParsing
    $uri2 = Invoke-WebRequest -MaximumRedirection 0 -Uri $uri.Headers.Location -ErrorAction SilentlyContinue -UseBasicParsing
    $file = $uri2.Headers.Location -split "/" | Select-Object -Last 1
    $file -match "\d+(\.\d+)+"
    $version = $Matches[0]
    return @{Version = $version; URL32 = $uri2.Headers.Location}
}

function global:au_SearchReplace {
    @{
        "tools\chocolateyInstall.ps1" = @{
            "(?i)(^\s*url\s*=\s*)('.*')"      = "`$1'$($Latest.URL32)'"
            "(?i)(^\s*checksum\s*=\s*)('.*')" = "`$1'$($Latest.checksum_zip)'"
        }
    }
}

update -ChecksumFor none -NoCheckUrl