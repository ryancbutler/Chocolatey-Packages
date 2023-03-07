$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/c/4/4/c44313c5-f04a-4034-8a22-967481b23975/FSLogix_Apps_2.9.8440.42104.zip'
  checksum     = 'F6273EC30862815EBB0CA2E634A24972BF86A042ED297A8F17F0F65A541E335B'
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
