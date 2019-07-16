$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://aka.ms/fslogix_download'
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

  checksum      = '1A715B69D23D2E523A138BD169D4B46D560CCF1873203A62855159A710DA13DA'
  checksumType  = 'sha256'

  checksum64      = 'AC9E0401DA3998AF1B246E3742F504980C6E98AE74AFF9CB35852CD72F230613'
  checksumType64  = 'sha256'

  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyPackage @packageArgs
remove-item $ziplocation -Force -Verbose -ErrorAction 0
remove-item $extractedlocation -Force -Recurse -Verbose -ErrorAction 0

