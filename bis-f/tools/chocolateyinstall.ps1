$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'MSI'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.7/setup-BIS-F-7.1912.7.11042.MSI' 	
  softwareName  = 'bis-f*'

  checksum      = 'ac759af55b4efd345f6e4f150ae0f4e9d100ea0d8d4ae273f20c1c1bab12ce8f'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart /l*v `"$env:TEMP\chocolatey\$($packageName)\$($packageName).MsiInstall.log`""
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
