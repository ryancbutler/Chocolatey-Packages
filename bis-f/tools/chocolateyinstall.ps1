$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.3/setup-BIS-F-6.1.3_build01.110.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '61bb90b0e312517bfe4026b7222968df4811ec1fb80c7e96d20e601718351100'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
