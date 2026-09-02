Describe 'Nuspec primitives' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/ChocoPkg.psm1" -Force
        $script:FixtureSource = Join-Path $PSScriptRoot 'fixtures/sample.nuspec'
    }

    BeforeEach {
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:WorkDir | Out-Null
        $script:NuspecPath = Join-Path $script:WorkDir 'sample.nuspec'
        Copy-Item $script:FixtureSource $script:NuspecPath
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:WorkDir -ErrorAction SilentlyContinue
    }

    Describe 'Get-NuspecVersion / Get-NuspecId' {
        It 'reads the metadata version, not a dependency version attribute' {
            Get-NuspecVersion -Path $script:NuspecPath | Should -BeExactly '3.25.202.4223'
        }

        It 'reads the package id' {
            Get-NuspecId -Path $script:NuspecPath | Should -BeExactly 'fslogix'
        }
    }

    Describe 'Set-NuspecVersion' {
        It 'changes the version and leaves every other byte alone' {
            $before = [System.IO.File]::ReadAllText($script:NuspecPath)

            Set-NuspecVersion -Path $script:NuspecPath -Version '9.9.9.9'

            $after = [System.IO.File]::ReadAllText($script:NuspecPath)
            Get-NuspecVersion -Path $script:NuspecPath | Should -BeExactly '9.9.9.9'
            $after.Replace('<version>9.9.9.9</version>', '<version>3.25.202.4223</version>') |
                Should -BeExactly $before
        }

        It 'does not add a BOM' {
            Set-NuspecVersion -Path $script:NuspecPath -Version '9.9.9.9'

            $bytes = [System.IO.File]::ReadAllBytes($script:NuspecPath)
            @($bytes[0], $bytes[1], $bytes[2]) | Should -Not -Be @(0xEF, 0xBB, 0xBF)
            $bytes[0] | Should -Be 0x3C   # '<'
        }

        It 'leaves the dependency version attribute untouched' {
            Set-NuspecVersion -Path $script:NuspecPath -Version '9.9.9.9'

            [System.IO.File]::ReadAllText($script:NuspecPath) |
                Should -Match ([regex]::Escape('version="1.0.20160915"'))
        }
    }

    Describe 'Test-VersionIsNewer' {
        It 'is true when the candidate is greater' {
            Test-VersionIsNewer -Candidate '3.26.826.17182' -Current '3.25.202.4223' | Should -BeTrue
        }

        It 'is false when the versions are equal' {
            Test-VersionIsNewer -Candidate '3.25.202.4223' -Current '3.25.202.4223' | Should -BeFalse
        }

        It 'is false when the candidate is lower' {
            Test-VersionIsNewer -Candidate '3.24.0.0' -Current '3.25.202.4223' | Should -BeFalse
        }

        It 'throws on an unparseable candidate' {
            { Test-VersionIsNewer -Candidate 'not-a-version' -Current '1.0' } | Should -Throw
        }
    }
}
