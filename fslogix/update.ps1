import-module au

$body = Invoke-WebRequest "https://learn.microsoft.com/en-us/fslogix/overview-release-notes"
$foundversion =@()
foreach ($link in $body.Links|where-object {$_.'data-linktype' -eq "external"}) {
    if($link.outerHTML  -match '\(([^\)]+)\)')
    {
        $foundversion += [PSCustomObject]@{
            version = [version]$matches[1]
            url = $link.href
        }
}
}

$recent = $foundversion|sort-object version -Descending|Select-Object -First 1

function global:au_BeforeUpdate {
    mkdir temp -Force
    Invoke-WebRequest -Uri $recent.url -ErrorAction stop -SkipCertificateCheck -SkipHeaderValidation -MaximumRetryCount 3 -RetryIntervalSec 5 -outfile "temp\fslogix.zip" -Verbose
    $Latest.checksum_zip = Get-FileHash temp\fslogix.zip | ForEach-Object Hash

}

function global:au_GetLatest {

    return @{Version = $recent.version; URL32 = $recent.url }
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