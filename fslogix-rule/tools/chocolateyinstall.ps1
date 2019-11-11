$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://download.microsoft.com/download/5/8/4/58482cbd-4072-4e26-9015-aa4bbe56c52e/FSLogix_Apps_2.9.7205.27375.zip'
  checksum = 'B7834E57127EB3558CADAA24578996F6CC4D826964C9AE3BFC349E6A37753380'
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
