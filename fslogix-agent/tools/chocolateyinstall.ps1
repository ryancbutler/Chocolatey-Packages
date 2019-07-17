﻿$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://aka.ms/fslogix_download'
  checksum = "25CBE46B0946E435198E9D1F0306BC41195E44ADC5B1C8BB1C5682E31DD7DC22" 
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'exe'
  file = "$extractedlocation\Win32\Release\FSLogixAppsSetup.exe"
  file64 = "$extractedlocation\x64\Release\FSLogixAppsSetup.exe"
  softwareName  = 'FSLogixAppsSetup*'

  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $ziplocation -Force -Verbose -ErrorAction 0
remove-item $extractedlocation -Force -Recurse -Verbose -ErrorAction 0

