$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://aka.ms/fslogix_download'
  checksum = 'B7834E57127EB3558CADAA24578996F6CC4D826964C9AE3BFC349E6A37753380'
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'exe'
  file = "$extractedlocation\Win32\Release\FSLogixAppsJavaRuleEditorSetup.exe"
  file64 = "$extractedlocation\x64\Release\FSLogixAppsJavaRuleEditorSetup.exe"
  softwareName  = 'FSLogixAppsJavaRuleEditorSetup*'

  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0

