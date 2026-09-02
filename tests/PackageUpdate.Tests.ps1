Describe 'Package update orchestration' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../lib/ChocoPkg.psm1" -Force
        $script:NuspecFixture  = Join-Path $PSScriptRoot 'fixtures/sample.nuspec'
        $script:InstallFixture = Join-Path $PSScriptRoot 'fixtures/sample-install.ps1'

        # Defined inside BeforeAll (rather than as a bare statement in the Describe
        # body) so it survives into Pester 5's Run phase: code directly in a
        # Describe/Context block only executes during Discovery, and a plain
        # `function` there is gone by the time It blocks run.
        function New-TestUpdateScript {
            param([string] $PackageDir, [string] $Version, [string] $Url, [string] $Checksum)

            $content = @"
[CmdletBinding()] param()
[pscustomobject]@{
    Version  = '$Version'
    Url      = '$Url'
    Checksum = '$Checksum'
}
"@
            Set-Content -LiteralPath (Join-Path $PackageDir 'update.ps1') -Value $content -Encoding utf8
        }
    }

    BeforeEach {
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        $script:PkgDir = Join-Path $script:Root 'fslogix'
        New-Item -ItemType Directory -Path (Join-Path $script:PkgDir 'tools') -Force | Out-Null
        Copy-Item $script:NuspecFixture  (Join-Path $script:PkgDir 'fslogix.nuspec')
        Copy-Item $script:InstallFixture (Join-Path $script:PkgDir 'tools/chocolateyinstall.ps1')
        $script:ArtifactDir = Join-Path $script:Root 'artifacts'
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:Root -ErrorAction SilentlyContinue
    }

    Describe 'Get-ChocoPackage' {
        It 'finds directories holding both a nuspec and an update.ps1' {
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '1.0' -Url 'https://example.test/a.zip' -Checksum 'aaa'

            $packages = @(Get-ChocoPackage -Root $script:Root)

            $packages.Count | Should -Be 1
            $packages[0].Name | Should -BeExactly 'fslogix'
            $packages[0].NuspecPath | Should -BeLike '*fslogix.nuspec'
        }

        It 'ignores a directory whose update script is retired to update.ps1.old' {
            $retired = Join-Path $script:Root 'fslogix-java'
            New-Item -ItemType Directory -Path $retired -Force | Out-Null
            Copy-Item $script:NuspecFixture (Join-Path $retired 'fslogix-java.nuspec')
            Set-Content -LiteralPath (Join-Path $retired 'update.ps1.old') -Value '# retired'
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '1.0' -Url 'https://example.test/a.zip' -Checksum 'aaa'

            @(Get-ChocoPackage -Root $script:Root).Name | Should -Be @('fslogix')
        }
    }

    Describe 'Invoke-PackageUpdate' {
        BeforeEach {
            # The mock body binds against the REAL Invoke-ChocoPack parameters, so this
            # is $OutputDirectory (its parameter name), not $ArtifactDirectory.
            Mock -ModuleName ChocoPkg Invoke-ChocoPack { Join-Path $OutputDirectory 'fslogix.9.9.9.9.nupkg' }
            Mock -ModuleName ChocoPkg Invoke-ChocoPush { [pscustomobject]@{ Outcome = 'pushed'; Output = 'ok' } }
        }

        It 'reports no change when the detected version is not newer' {
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '3.25.202.4223' -Url 'https://example.test/a.zip' -Checksum 'aaa'
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY'

            $result.Outcome | Should -BeExactly 'no change'
            Get-NuspecVersion -Path $pkg.NuspecPath | Should -BeExactly '3.25.202.4223'
            Should -Invoke -ModuleName ChocoPkg Invoke-ChocoPush -Times 0 -Exactly
        }

        It 'bumps, packs and pushes when a newer version is detected' {
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '9.9.9.9' -Url 'https://example.test/new.zip' -Checksum 'newsum'
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY'

            $result.Outcome | Should -BeExactly 'pushed'
            $result.DetectedVersion | Should -BeExactly '9.9.9.9'
            Get-NuspecVersion -Path $pkg.NuspecPath | Should -BeExactly '9.9.9.9'
            $install = [System.IO.File]::ReadAllText((Join-Path $script:PkgDir 'tools/chocolateyinstall.ps1'))
            $install | Should -Match ([regex]::Escape("'https://example.test/new.zip'"))
            $install | Should -Match ([regex]::Escape("'newsum'"))
            $result.ChangedFiles.Count | Should -Be 2
        }

        It 'writes nothing in CheckOnly mode' {
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '9.9.9.9' -Url 'https://example.test/new.zip' -Checksum 'newsum'
            $pkg = Get-ChocoPackage -Root $script:Root
            $before = [System.IO.File]::ReadAllText($pkg.NuspecPath)

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY' -CheckOnly

            $result.Outcome | Should -BeExactly 'checked'
            [System.IO.File]::ReadAllText($pkg.NuspecPath) | Should -BeExactly $before
            Should -Invoke -ModuleName ChocoPkg Invoke-ChocoPack -Times 0 -Exactly
        }

        It 'bumps and packs but does not push in NoPush mode' {
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '9.9.9.9' -Url 'https://example.test/new.zip' -Checksum 'newsum'
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY' -NoPush

            $result.Outcome | Should -BeExactly 'packed'
            Get-NuspecVersion -Path $pkg.NuspecPath | Should -BeExactly '9.9.9.9'
            Should -Invoke -ModuleName ChocoPkg Invoke-ChocoPush -Times 0 -Exactly
        }

        It 'updates an equal version when Force is set' {
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '3.25.202.4223' -Url 'https://example.test/same.zip' -Checksum 'samesum'
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY' -Force

            $result.Outcome | Should -BeExactly 'pushed'
        }

        It 'reports already published without changing the outcome to failed' {
            Mock -ModuleName ChocoPkg Invoke-ChocoPush { [pscustomobject]@{ Outcome = 'already published'; Output = '(409) Conflict' } }
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '9.9.9.9' -Url 'https://example.test/new.zip' -Checksum 'newsum'
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY'

            $result.Outcome | Should -BeExactly 'already published'
            $result.ChangedFiles.Count | Should -Be 2
        }

        It 'clears ChangedFiles and reports failed when the push retries are exhausted' {
            Mock -ModuleName ChocoPkg Invoke-ChocoPush { [pscustomobject]@{ Outcome = 'failed'; Output = 'boom' } }
            Mock -ModuleName ChocoPkg Start-Sleep { }
            New-TestUpdateScript -PackageDir $script:PkgDir -Version '9.9.9.9' -Url 'https://example.test/new.zip' -Checksum 'newsum'
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY'

            $result.Outcome | Should -BeExactly 'failed'
            $result.ChangedFiles.Count | Should -Be 0
            Should -Invoke -ModuleName ChocoPkg Invoke-ChocoPush -Times 3 -Exactly
        }

        It 'records a failure instead of throwing when the update script throws' {
            Set-Content -LiteralPath (Join-Path $script:PkgDir 'update.ps1') -Value 'throw "upstream unavailable"' -Encoding utf8
            $pkg = Get-ChocoPackage -Root $script:Root

            # DetectAttempts 1 so the test does not sit through the retry backoff.
            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY' -DetectAttempts 1

            $result.Outcome | Should -BeExactly 'failed'
            "$($result.Error)" | Should -Match 'upstream unavailable'
        }

        It 'fails when the update script omits a required key' {
            Set-Content -LiteralPath (Join-Path $script:PkgDir 'update.ps1') -Value '[pscustomobject]@{ Version = "9.9.9.9" }' -Encoding utf8
            $pkg = Get-ChocoPackage -Root $script:Root

            $result = Invoke-PackageUpdate -Package $pkg -ArtifactDirectory $script:ArtifactDir -ApiKey 'KEY'

            $result.Outcome | Should -BeExactly 'failed'
            "$($result.Error)" | Should -Match 'Url'
        }
    }
}
