$packageArgs = @{
  packageName   = $env:ChocolateyPackageName
  fileType      = 'EXE'
  url 			    = 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.2/setup-BIS-F-7.1912.2.11029.exe' 	
  softwareName  = 'bis-f*'

  checksum      = '35d1251bd7fbf03dc2ccfdac874db7e862ae352c74dae9430e6a1ae77bdbc7f7'
  checksumType  = 'sha256'

  silentArgs    = "/qn /norestart"
  validExitCodes= @(0, 3010, 1641)
}

Install-ChocolateyPackage @packageArgs
