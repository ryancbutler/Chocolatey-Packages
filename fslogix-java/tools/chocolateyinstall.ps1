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
  file = "$extractedlocation\Win32\Release\FSLogixAppsJavaRuleEditorSetup.exe"
  file64 = "$extractedlocation\x64\Release\FSLogixAppsJavaRuleEditorSetup.exe"
  softwareName  = 'FSLogixAppsJavaRuleEditorSetup*'

  checksum      = '9CCD684C243140EB932A066927C7DE0E94500578440808500CA41258D4DA9898'
  checksumType  = 'sha256'

  checksum64      = '413A5320C5E514A3EFF3F586984DD010FDF432019752E1FD0027B586EED15E9D'
  checksumType64  = 'sha256'

  silentArgs    = "/install /quiet /norestart"
  validExitCodes= @(0, 3010)
}

Install-ChocolateyPackage @packageArgs
remove-item $ziplocation -Force -Verbose -ErrorAction 0
remove-item $extractedlocation -Force -Recurse -Verbose -ErrorAction 0

