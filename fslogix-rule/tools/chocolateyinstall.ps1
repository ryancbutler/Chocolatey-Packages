$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url = 'https://download.microsoft.com/download/3/a/f/3af0c274-2bf9-4916-a70b-f5556595fbf2/FSLogix_Apps_2.9.7838.44263.zip'
  checksum = 'B4496DE36FFC98A8C8D3636B1AA2408C1FC21B04ECF36AA66F93AC0A678F752D'
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
