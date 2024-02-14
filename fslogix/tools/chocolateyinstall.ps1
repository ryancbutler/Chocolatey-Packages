$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/1/7/1/17134492-1ef3-420b-a78a-cf13c42d1078/FSLogix_Apps_2.9.8784.63912.zip'
  checksum     = '772408B5ABDDAD7415DBC711B1E7416481F7A508C542FD2AB6404C16C220CF9F'
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
  file           = "$extractedlocation\Win32\Release\FSLogixAppsSetup.exe"
  file64         = "$extractedlocation\x64\Release\FSLogixAppsSetup.exe"
  softwareName   = 'FSLogixAppsSetup*'

  silentArgs     = "/install /quiet /norestart"
  validExitCodes = @(0, 3010)
}

Install-ChocolateyInstallPackage @packageArgs
remove-item $toolsDir -Force -Recurse -Verbose -ErrorAction 0

