import-module au

function global:au_BeforeUpdate {
    #$Latest.Checksum32 = Get-RemoteChecksum $Latest.URL32 
    #Get-RemoteFiles -Purge -NoSuffix 
}

function global:au_GetLatest {
    $download_page = Invoke-WebRequest -Uri "https://github.com/EUCweb/BIS-F/releases/latest" -UseBasicParsing #1
    $regex   = '.exe$'
    $url     = "https://github.com" + ($download_page.links | ? href -match $regex | select -First 1 -expand href)
    $version = $url -split '-|.exe' | select -Last 1 -Skip 2
    $version = $url -split "/" | select -Last 1 -Skip 1
    write-host $version
    return @{Version = $version; URL32 = $url}
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
