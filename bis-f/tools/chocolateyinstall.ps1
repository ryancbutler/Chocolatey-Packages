$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'MSI'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.6/setup-BIS-F-7.1912.6.11041.MSI' 	
  softwareName  = 'bis-f*'

  checksum      = 'c491823b09769578481628787ab98b59142194674db9b017e0489fd61e9b0620'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart /l*v `"$env:TEMP\chocolatey\$($packageName)\$($packageName).MsiInstall.log`""
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
