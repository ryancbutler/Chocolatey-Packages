$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.0.01.102/setup-BIS-F-6.1.0_build01.102.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '2D1106FAAD0CFE31CA93A78430DBECC8C7EC5F5F1FDC71DA6080DD914E352E39'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs