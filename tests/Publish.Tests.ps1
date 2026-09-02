BeforeAll {
    Import-Module "$PSScriptRoot/../lib/ChocoPkg.psm1" -Force
}

Describe 'Get-ChocoPushArgs' {
    It 'builds the argument array in order' {
        Get-ChocoPushArgs -NupkgPath 'C:\a\fslogix.1.2.3.nupkg' -Source 'https://push.chocolatey.org' -ApiKey 'KEY' |
            Should -Be @('push', 'C:\a\fslogix.1.2.3.nupkg', '--source', 'https://push.chocolatey.org', '--api-key', 'KEY', '--limit-output')
    }

    It 'never emits an empty argument' {
        # Regression test: AU passed a conditionally-empty '--force' slot. Windows
        # PowerShell dropped it; PowerShell 7 forwards it as a real "" argument,
        # which chocolatey joined into the package path as a trailing space.
        $pushArgs = Get-ChocoPushArgs -NupkgPath 'C:\a\fslogix.1.2.3.nupkg' -Source 'https://push.chocolatey.org' -ApiKey 'KEY'

        $pushArgs | Should -Not -Contain ''
        foreach ($a in $pushArgs) { [string]::IsNullOrWhiteSpace($a) | Should -BeFalse }
    }

    It 'throws rather than emitting a blank slot when the api key is missing' {
        { Get-ChocoPushArgs -NupkgPath 'C:\a\x.nupkg' -Source 'https://push.chocolatey.org' -ApiKey '' } |
            Should -Throw
    }

    It 'throws when the nupkg path is whitespace' {
        { Get-ChocoPushArgs -NupkgPath '   ' -Source 'https://push.chocolatey.org' -ApiKey 'KEY' } |
            Should -Throw
    }
}

Describe 'Test-DuplicateVersionOutput' {
    It 'recognises the community feed duplicate-version rejection' {
        $output = @"
Attempting to push fslogix.3.26.826.17182.nupkg to https://push.chocolatey.org/
Failed to process request. 'A package with ID 'fslogix' and version '3.26.826.17182' already exists and cannot be modified.'
The remote server returned an error: (409) Conflict..
"@
        Test-DuplicateVersionOutput -Output $output | Should -BeTrue
    }

    It 'does not treat an auth failure as a duplicate' {
        $output = @"
Failed to process request. 'The specified API key is invalid.'
The remote server returned an error: (403) Forbidden..
"@
        Test-DuplicateVersionOutput -Output $output | Should -BeFalse
    }

    It 'does not treat the malformed-path failure as a duplicate' {
        # This is the exact text of the outage this engine replaces.
        $output = "Chocolatey v2.7.4 File specified is either not found or not a .nupkg file. 'fslogix.3.26.826.17182.nupkg '"

        Test-DuplicateVersionOutput -Output $output | Should -BeFalse
    }
}

Describe 'Invoke-WithRetry' {
    It 'returns the value on first success without delay' {
        Invoke-WithRetry -ScriptBlock { 'ok' } -Attempts 3 -DelaySeconds 0 | Should -Be 'ok'
    }

    It 'retries until the scriptblock succeeds' {
        $script:calls = 0
        $result = Invoke-WithRetry -ScriptBlock {
            $script:calls++
            if ($script:calls -lt 3) { throw 'transient' }
            'recovered'
        } -Attempts 3 -DelaySeconds 0

        $result | Should -Be 'recovered'
        $script:calls | Should -Be 3
    }

    It 'rethrows after exhausting attempts' {
        { Invoke-WithRetry -ScriptBlock { throw 'always fails' } -Attempts 2 -DelaySeconds 0 } |
            Should -Throw -ExpectedMessage '*always fails*'
    }
}

Describe 'Get-UrlChecksum caching' {
    It 'returns the cached value without downloading again' {
        Clear-UrlChecksumCache
        Mock -ModuleName ChocoPkg Invoke-WebRequest {
            [System.IO.File]::WriteAllText($OutFile, 'payload')
        }

        $first  = Get-UrlChecksum -Url 'https://example.test/a.zip'
        $second = Get-UrlChecksum -Url 'https://example.test/a.zip'

        $second | Should -BeExactly $first
        $first | Should -BeExactly $first.ToLowerInvariant()
        Should -Invoke -ModuleName ChocoPkg Invoke-WebRequest -Times 1 -Exactly
    }
}

Describe 'Invoke-ChocoPack' {
    BeforeEach {
        $script:PackRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:PackRoot -Force | Out-Null
        $script:PackNuspec = Join-Path $script:PackRoot 'fslogix.nuspec'
        Copy-Item (Join-Path $PSScriptRoot 'fixtures/sample.nuspec') $script:PackNuspec
        $script:PackOut = Join-Path $script:PackRoot 'artifacts'
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:PackRoot -ErrorAction SilentlyContinue
    }

    It 'returns only the nupkg path when choco pack writes to stdout' {
        # Regression: `& choco pack` left its own stdout in the success stream, so
        # this function returned an array of (choco output + path). That array
        # could not bind to the [string] NupkgPath parameter of Invoke-ChocoPush,
        # failing every package with "Cannot process argument transformation on
        # parameter 'NupkgPath'".
        Mock -ModuleName ChocoPkg choco {
            $outDir = $args[$args.IndexOf('--output-directory') + 1]
            New-Item -ItemType File -Path (Join-Path $outDir 'fslogix.3.25.202.4223.nupkg') -Force | Out-Null
            'Attempting to build package from ''fslogix.nuspec''.'
            'Successfully created package ''fslogix.3.25.202.4223.nupkg'''
            $global:LASTEXITCODE = 0
        }

        $result = Invoke-ChocoPack -NuspecPath $script:PackNuspec -OutputDirectory $script:PackOut

        @($result).Count | Should -Be 1
        $result | Should -BeOfType ([string])
        $result | Should -BeExactly (Join-Path (Resolve-Path -LiteralPath $script:PackOut).ProviderPath 'fslogix.3.25.202.4223.nupkg')
    }

    It 'produces a path that binds to the Invoke-ChocoPush NupkgPath parameter' {
        Mock -ModuleName ChocoPkg choco {
            $outDir = $args[$args.IndexOf('--output-directory') + 1]
            New-Item -ItemType File -Path (Join-Path $outDir 'fslogix.3.25.202.4223.nupkg') -Force | Out-Null
            'Successfully created package'
            $global:LASTEXITCODE = 0
        }

        $nupkg = Invoke-ChocoPack -NuspecPath $script:PackNuspec -OutputDirectory $script:PackOut

        { Get-ChocoPushArgs -NupkgPath $nupkg -Source 'https://push.chocolatey.org' -ApiKey 'KEY' } |
            Should -Not -Throw
    }

    It 'surfaces the choco output when pack fails' {
        Mock -ModuleName ChocoPkg choco {
            'ERROR: The nuspec file is invalid.'
            $global:LASTEXITCODE = 1
        }

        { Invoke-ChocoPack -NuspecPath $script:PackNuspec -OutputDirectory $script:PackOut } |
            Should -Throw -ExpectedMessage '*nuspec file is invalid*'
    }
}
