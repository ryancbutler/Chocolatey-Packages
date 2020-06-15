$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.3/setup-BIS-F-7.1912.3.11036.exe' 	
  softwareName  = 'bis-f*'

  checksum      = 'ee3e60afa6b526b08a21c56304af1a3623d7a28f713463bca2ca7e1e11ca0783'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
