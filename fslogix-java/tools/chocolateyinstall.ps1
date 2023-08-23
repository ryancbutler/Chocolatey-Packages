$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/9/7/b/97b4c64b-ffc9-447c-b39e-3afba4672ee8/FSLogix_Apps_2.9.8612.60056.zip'
  checksum     = 'E13808071BACD73FB47E37DA35E0EB53B1562B7E11A944BDC9C6FE55BD19051F'
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  file           = "$extractedlocation\Win32\Release\FSLogixAppsJavaRuleEditorSetup.exe"
  file64         = "$extractedlocation\x64\Release\FSLogixAppsJavaRuleEditorSetup.exe"
  softwareName   = 'FSLogixAppsJavaRuleEditorSetup*'

  silentArgs     = "/install /quiet /norestart"
  validExitCodes = @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0

