Describe 'Package file rewriting' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/ChocoPkg.psm1" -Force
        $script:FixtureSource = Join-Path $PSScriptRoot 'fixtures/sample-install.ps1'
    }

    BeforeEach {
        $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:WorkDir | Out-Null
        $script:FilePath = Join-Path $script:WorkDir 'chocolateyinstall.ps1'
        Copy-Item $script:FixtureSource $script:FilePath
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:WorkDir -ErrorAction SilentlyContinue
    }

    Describe 'Update-PackageFile' {
        It 'rewrites the url and checksum lines' {
            $replacements = Get-DefaultReplacements -Url 'https://example.test/new.zip' -Checksum 'abc123'

            Update-PackageFile -Path $script:FilePath -Replacements $replacements

            $text = [System.IO.File]::ReadAllText($script:FilePath)
            $text | Should -Match ([regex]::Escape("url          = 'https://example.test/new.zip'"))
            $text | Should -Match ([regex]::Escape("checksum     = 'abc123'"))
        }

        It 'writes a dollar-sign-bearing URL literally instead of treating it as a regex substitution token' {
            $replacements = Get-DefaultReplacements -Url 'https://x.test/a$1b.zip' -Checksum 'abc123'

            Update-PackageFile -Path $script:FilePath -Replacements $replacements

            $text = [System.IO.File]::ReadAllText($script:FilePath)
            $text | Should -Match ([regex]::Escape("url          = 'https://x.test/a`$1b.zip'"))
        }

        It 'does not touch the checksumtype line' {
            $replacements = Get-DefaultReplacements -Url 'https://example.test/new.zip' -Checksum 'abc123'

            Update-PackageFile -Path $script:FilePath -Replacements $replacements

            [System.IO.File]::ReadAllText($script:FilePath) |
                Should -Match ([regex]::Escape('checksumtype = "sha256"'))
        }

        It 'preserves the UTF-8 BOM' {
            $replacements = Get-DefaultReplacements -Url 'https://example.test/new.zip' -Checksum 'abc123'

            Update-PackageFile -Path $script:FilePath -Replacements $replacements

            $bytes = [System.IO.File]::ReadAllBytes($script:FilePath)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'preserves CRLF line endings' {
            $replacements = Get-DefaultReplacements -Url 'https://example.test/new.zip' -Checksum 'abc123'

            Update-PackageFile -Path $script:FilePath -Replacements $replacements

            $text = [System.IO.File]::ReadAllText($script:FilePath)
            $text | Should -Match "`r`n"
            $text | Should -Not -Match "(?<!`r)`n"
        }

        It 'is idempotent - applying the same values twice does not throw' {
            $replacements = Get-DefaultReplacements -Url 'https://example.test/new.zip' -Checksum 'abc123'

            Update-PackageFile -Path $script:FilePath -Replacements $replacements
            $first = [System.IO.File]::ReadAllText($script:FilePath)

            { Update-PackageFile -Path $script:FilePath -Replacements $replacements } | Should -Not -Throw
            [System.IO.File]::ReadAllText($script:FilePath) | Should -BeExactly $first
        }

        It 'throws when a pattern matches nothing' {
            { Update-PackageFile -Path $script:FilePath -Replacements @{ '^\s*nosuchkey\s*=\s*(.*)$' = 'x' } } |
                Should -Throw -ExpectedMessage '*matched nothing*'
        }

        It 'throws when the file does not exist' {
            { Update-PackageFile -Path (Join-Path $script:WorkDir 'missing.ps1') -Replacements @{ 'a' = 'b' } } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }
}
