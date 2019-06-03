$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.1.01.105/setup-BIS-F-6.1.1_build01.105.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '45febe299dea83ccba8399e4389fd5e20251c907daca4d906c04dba28bb3d78b'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
