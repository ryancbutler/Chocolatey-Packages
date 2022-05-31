$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/e/a/1/ea1bcf0a-e66d-48d2-ac9f-e385e5a7456e/FSLogix_Apps_2.9.8171.14983.zip'
  checksum     = 'B89C123D5E7615300FC0B3DC7617267370347486E44FDB3B9441C50E9AC3CF67'
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
