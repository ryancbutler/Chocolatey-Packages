$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://download.microsoft.com/download/3/d/b/3db5e2a7-bd14-4ac1-ae0f-373e0e7c2f41/FSLogix_Apps_2.9.7349.30108.zip'
  checksum = 'FE1A07579122D2DAC1D84728456954D11FBDDD26BC664E319DE83F9B9E1766E5'
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'exe'
  file = "$extractedlocation\Win32\Release\FSLogixAppsRuleEditorSetup.exe"
  file64 = "$extractedlocation\x64\Release\FSLogixAppsRuleEditorSetup.exe"
  softwareName  = 'FSLogixAppsRuleEditorSetup.exe*'
  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0
