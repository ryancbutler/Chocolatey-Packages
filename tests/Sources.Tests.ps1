BeforeAll {
    Import-Module "$PSScriptRoot/../lib/Sources.psm1" -Force
    $script:Html = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/fslogix-release-notes.html'))
    $script:Release = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/github-latest-release.json')) | ConvertFrom-Json
}

Describe 'Select-FsLogixReleaseFromHtml' {
    It 'picks the highest version among external links' {
        $result = Select-FsLogixReleaseFromHtml -Html $script:Html

        $result.Version | Should -BeExactly '3.26.826.17182'
        $result.Url | Should -BeExactly 'https://download.microsoft.com/download/aaa/FSLogix_26.08.zip'
    }

    It 'ignores non-external links even when they carry a higher version' {
        (Select-FsLogixReleaseFromHtml -Html $script:Html).Version | Should -Not -Be '3.99.0.0'
    }

    It 'returns the version string verbatim rather than round-tripping through [version]' {
        $html = '<a href="https://example.test/x.zip" data-linktype="external">FSLogix (25.02)</a>'

        (Select-FsLogixReleaseFromHtml -Html $html).Version | Should -BeExactly '25.02'
    }

    It 'throws when no versioned external link is present' {
        { Select-FsLogixReleaseFromHtml -Html '<html><body>nothing here</body></html>' } |
            Should -Throw -ExpectedMessage '*no*version*'
    }
}

Describe 'Select-MsiAssetFromRelease' {
    It 'selects the MSI asset and strips the leading v from the tag' {
        $result = Select-MsiAssetFromRelease -Release $script:Release

        $result.Version | Should -BeExactly '7.1912.6'
        $result.Url | Should -BeExactly 'https://github.com/EUCweb/BIS-F/releases/download/7.1912.6/setup-BIS-F-7.1912.6.11041.MSI'
    }

    It 'throws when the release has no MSI asset' {
        $release = [pscustomobject]@{
            tag_name = 'v1.0'
            assets   = @([pscustomobject]@{ browser_download_url = 'https://example.test/a.zip' })
        }

        { Select-MsiAssetFromRelease -Release $release } | Should -Throw -ExpectedMessage '*MSI*'
    }
}
