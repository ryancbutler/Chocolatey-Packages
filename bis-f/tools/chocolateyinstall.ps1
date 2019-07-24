$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.2/setup-BIS-F-6.1.2_build01.109.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '3368bff518d122312ac7972cf156db7a60d2de7f5962d6830b87a1210296d297'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
