$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://download.microsoft.com/download/3/d/d/3ddfe262-56c7-496c-9af6-82602d2d7b5d/FSLogix_Apps_2.9.7237.48865.zip'
  checksum = '77A4BD939A275D9356090A1E576A4BC653C78D46F6A6601C69D6F92DE5076D6C'
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
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0

