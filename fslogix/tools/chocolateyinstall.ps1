$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://download.microsoft.com/download/9/e/7/9e77e5f5-01e7-4419-a39a-0502b2ff2d8d/FSLogix_Apps_2.9.7621.30127.zip'
  checksum = '047E3697B93F9CF47C639452C275AE41F9D6252DA0A310DB93F5A1686D33D55C'
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

