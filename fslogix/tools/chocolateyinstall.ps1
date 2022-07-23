$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/d/1/9/d190de51-f1c1-4581-9007-24e5a812d6e9/FSLogix_Apps_2.9.8228.50276.zip'
  checksum     = '7FB3EB2EA44C2BE3AEF71C698401C90DB02B85336952B25096B9158656692A64'
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  file           = "$extractedlocation\Win32\Release\FSLogixAppsSetup.exe"
  file64         = "$extractedlocation\x64\Release\FSLogixAppsSetup.exe"
  softwareName   = 'FSLogixAppsSetup*'

  silentArgs     = "/install /quiet /norestart"
  validExitCodes = @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0

