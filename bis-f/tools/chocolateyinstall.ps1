$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.2/setup-BIS-F-6.1.2_build01.108.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '98d7d7a38b830944048f972f0a0c53c0726f6080b46ef54ef72a3888d7395105'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
