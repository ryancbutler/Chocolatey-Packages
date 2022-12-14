$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/0/a/4/0a4c3a18-f6c8-4bcd-91fc-97ce845e2d3e/FSLogix_Apps_2.9.8361.52326.zip'
  checksum     = 'C3E5BE03C8E151F209FF55BE93D168EB370E1B1DED9A6A0E8EEEAEC9FB710CFE'
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  file           = "$extractedlocation\Win32\Release\FSLogixAppsRuleEditorSetup.exe"
  file64         = "$extractedlocation\x64\Release\FSLogixAppsRuleEditorSetup.exe"
  softwareName   = 'FSLogixAppsRuleEditorSetup.exe*'
  silentArgs     = "/install /quiet /norestart"
  validExitCodes = @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0
