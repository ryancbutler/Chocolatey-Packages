import-module au

function global:au_BeforeUpdate {
   #remove-item -Path "temp" -Force -Recurse
}

function global:au_GetLatest {
    $url = "https://aka.ms/fslogix_download"
    #mkdir temp -Force
    # $download_page = Invoke-WebRequest -Uri $url -UseBasicParsing -outfile "temp\fslogix.zip"
    # 7z e temp\fslogix.zip -otemp -spf -y
    # $Latest.checksum_zip = Get-FileHash temp\fslogix.zip | % Hash
    # $version = (get-item .\temp\x64\Release\FSLogixAppsSetup.exe).VersionInfo.FileVersion

    $uri = Invoke-WebRequest -MaximumRedirection 0 -Uri $url -ErrorAction SilentlyContinue -UseBasicParsing
    $uri2 = Invoke-WebRequest -MaximumRedirection 0 -Uri $uri.Headers.Location -ErrorAction SilentlyContinue -UseBasicParsing
    $file = $uri2.Headers.Location -split "/" | Select-Object -Last 1
    $file -match "\d+(\.\d+)+"
    $version = $Matches[0]
    #$Latest.checksum32 = Get-FileHash temp\Win32\Release\FSLogixAppsSetup.exe | % Hash
    #$Latest.checksum64 = Get-FileHash temp\x64\Release\FSLogixAppsSetup.exe | % Hash
    #$string = $url -split "/" | select -Last 1 -Skip 1
    #$version = $string.Remove(($string.LastIndexOf(".")),"1")
    #write-host $version
    return @{Version = $version; URL32 = $url}
}

function global:au_SearchReplace {
    @{
        "tools\chocolateyInstall.ps1" = @{
            "(?i)(^\s*checksum\s*=\s*)('.*')" = "`$1'$($Latest.checksum_zip )'"
            #"(?i)(^\s*checksum64\s*=\s*)('.*')" = "`$1'$($Latest.Checksum64)'"
        }
    }
}

update -ChecksumFor none -NoCheckUrl
#remove-item -Path "temp" -Force -Recurse