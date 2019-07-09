$toolsdir = "$env:TEMP\fslogix"
#Get ZIP
$ziplocation = Get-ChocolateyWebFile -Url 'https://aka.ms/fslogix_download' -GetOriginalFileName -fileFullPath $toolsdir -checksum "25CBE46B0946E435198E9D1F0306BC41195E44ADC5B1C8BB1C5682E31DD7DC22" -checksumtype "sha256"

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'exe'
  file = "$extractedlocation\Win32\Release\FSLogixAppsSetup.exe"
  file64 = "$extractedlocation\x64\Release\FSLogixAppsSetup.exe"
  softwareName  = 'FSLogixAppsSetup*'

  checksum      = '9BDBC32263610F0761C5862C24223147A508AE026673C58B232A4467A983B1DB'
  checksumType  = 'sha256'

  checksum64      = '2EC3CC513D4744E7054FE251A6D02F25296DDB8A8CB49A910A6481AF4007D245'
  checksumType64  = 'sha256'

  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyPackage @packageArgs
remove-item $ziplocation -Force -Verbose -ErrorAction 0
remove-item $extractedlocation -Force -Recurse -Verbose -ErrorAction 0

