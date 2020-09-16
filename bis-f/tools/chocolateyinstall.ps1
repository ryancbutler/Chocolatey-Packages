$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'MSI'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.5/setup-BIS-F-7.1912.5.11040.MSI' 	
  softwareName  = 'bis-f*'

  checksum      = '2708b001d1cdec30c86517a9c6d55e1b0876985d24ec2640d93145fd52faf3c0'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart /l*v `"$env:TEMP\chocolatey\$($packageName)\$($packageName).MsiInstall.log`""
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
