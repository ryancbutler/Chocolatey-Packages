Install-ChocolateyZipPackage -PackageName $env:ChocolateyPackageName `
 -Url 'https://aka.ms/fslogix_download' `
 -UnzipLocation $env:TEMP

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'exe'
  file = "$env:TEMP\Win32\Release\FSLogixAppsSetup.exe"
  file64 = "$env:TEMP\x64\Release\FSLogixAppsSetup.exe"
  url 			    = 'https://aka.ms/fslogix_download' 	
  softwareName  = 'FSLogixAppsSetup*'

  checksum      = '9BDBC32263610F0761C5862C24223147A508AE026673C58B232A4467A983B1DB'
  checksumType  = 'sha256'

  checksum64      = '2EC3CC513D4744E7054FE251A6D02F25296DDB8A8CB49A910A6481AF4007D245'
  checksumType64  = 'sha256'

  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyPackage @packageArgs
