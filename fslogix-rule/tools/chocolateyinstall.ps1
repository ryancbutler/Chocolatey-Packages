$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/9/7/b/97b4c64b-ffc9-447c-b39e-3afba4672ee8/FSLogix_Apps_2.9.8612.60056.zip'
  checksum     = '98B70935A88324ED32595164ABF452D6226055180B6A3444CB888BE6E9160A48'
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
