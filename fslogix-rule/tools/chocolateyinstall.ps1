$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/0d30db30-2d48-4640-a56c-3a1502fcb29a/FSLogix_25.02.zip'
  checksum     = 'ddd0fb24f68968aafd54f985dbd0a9e364d6d68d314023c055de3f921c411d7e'
  checksumtype = "sha256"
}

$ziplocation = Get-ChocolateyWebFile @zipargs -GetOriginalFileName

#Extract
$extractedlocation = Get-ChocolateyUnzip -FileFullPath $ziplocation -Destination $toolsDir -PackageName $env:ChocolateyPackageName

#Check for FSLogix folder path
$dirs = get-childitem -Path $extractedlocation -Directory -Filter "FSLogix*"
if ($dirs.count -gt 0) {
  $extractedlocation = $dirs[-1].FullName
}

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
