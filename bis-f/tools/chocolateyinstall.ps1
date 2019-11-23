$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.3/setup-BIS-F-6.1.3_build01.111.exe' 	
  softwareName  = 'bis-f*'

  checksum      = 'fd0b7d72b7917aef63069f009948774ae3ead903ef28e70a8cd96958d4f4a4fd'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
