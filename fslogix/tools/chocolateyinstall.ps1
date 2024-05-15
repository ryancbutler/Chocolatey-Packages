$toolsdir = "$env:TEMP\fslogix"

#Get ZIP
$zipargs = @{
  packageName  = $env:ChocolateyPackageName
  fileFullPath = $toolsdir
  url          = 'https://download.microsoft.com/download/e/c/4/ec4b55b3-d2f3-4610-aebd-56478eb0d582/FSLogix_Apps_2.9.8884.27471.zip'
  checksum     = '941F2BD91A7716A53E04550F901938B8FADE6C107F0E4BAB4847168B0BBBE5AC'
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

