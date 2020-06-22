$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'MSI'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.4/setup-BIS-F-7.1912.4.11038.msi' 	
  softwareName  = 'bis-f*'

  checksum      = '0213cf731f33266a4b94fec1bdeb74d801cd80c9cdcaee7ad679f6f7d145c33e'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart /l*v `"$env:TEMP\chocolatey\$($packageName)\$($packageName).MsiInstall.log`""
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
