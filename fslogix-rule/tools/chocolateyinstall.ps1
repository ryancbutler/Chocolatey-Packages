$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://download.microsoft.com/download/9/2/5/9257adcf-abdf-4ab3-b37f-416d70682315/FSLogix_Apps_2.9.8111.53415.zip'
  checksum = 'F8175EAEBBD9BB513B3FC02AF48717B4332CEDDCDB0109DE5C66405FED87E726'
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
