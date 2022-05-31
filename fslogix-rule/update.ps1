import-module au
#Leverages Evergreen API to pull data vs hitting Microsoft. Thanks Aaron Parker!
$url = "https://evergreen-api.stealthpuppy.com/app/MicrosoftFSLogixApps"

function global:au_BeforeUpdate {
    mkdir temp -Force
    Invoke-WebRequest -Uri $url -UseBasicParsing -outfile "temp\fslogix.zip" -Verbose -ErrorAction SilentlyContinue
    $Latest.checksum_zip = Get-FileHash temp\fslogix.zip | ForEach-Object Hash

}

function global:au_GetLatest {
    try {
        $response = invoke-restmethod -Uri $url -ErrorAction SilentlyContinue -UseBasicParsing
    }
    catch {
        return
    }
    return @{Version = $response.Version; URL32 = $response.URI }
}

function global:au_SearchReplace {
    @{
        "tools\chocolateyInstall.ps1" = @{
            "(?i)(^\s*url\s*=\s*)('.*')"      = "`$1'$($Latest.URL32)'"
            "(?i)(^\s*checksum\s*=\s*)('.*')" = "`$1'$($Latest.checksum_zip)'"
        }
    }
}

update -ChecksumFor none