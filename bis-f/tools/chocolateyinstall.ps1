$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.0/setup-BIS-F-7.1912.0.exe' 	
  softwareName  = 'bis-f*'

  checksum      = 'd13544ac931e16af04df923b02a2157c67d8c7adda3a32aa4af15f0b546a11ca'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
