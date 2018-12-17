$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/6.1.0.01.103/setup-BIS-F-6.1.0_build01.103.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '03A3EEAC5230036330FF50E6C7D59BCE3220F19AC797A575AC1E5EC1E5E473B0'
  checksumType  = 'sha256'

  silentArgs    = "/VERYSILENT /NORESTART"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs