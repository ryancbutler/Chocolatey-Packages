$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.3/setup-BIS-F-7.1912.3.11033.exe' 	
  softwareName  = 'bis-f*'

  checksum      = 'c8342a5606f074cd91c21eaf8a4a278bf2ed4ce886eb891dbe4765ec81ba6c81'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
