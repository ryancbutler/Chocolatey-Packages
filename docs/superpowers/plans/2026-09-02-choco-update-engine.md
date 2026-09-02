# Chocolatey Update Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the AU module with a small, testable PowerShell 7 engine that detects upstream releases, bumps package files, packs, pushes to Chocolatey, and commits — failing loudly when it cannot publish.

**Architecture:** Two modules plus a runner. `lib/ChocoPkg.psm1` holds publish primitives (nuspec read/write, file rewrite, checksum, pack, push) and a per-package orchestrator. `lib/Sources.psm1` holds upstream detectors, split into a network fetch and a pure parser so the parsing is unit-testable. Each `<pkg>/update.ps1` only detects and returns an object; the engine does everything else. Packages run sequentially in the runner's own process — no `Start-Job` fan-out.

**Tech Stack:** PowerShell 7 (runner is 7.6.5 on `windows-latest`), Pester 5, Chocolatey CLI 2.x, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-02-choco-update-engine-design.md`

## Global Constraints

- **PowerShell 7 only.** No Windows PowerShell 5.1 fallback, no AU module, no `Start-Job`.
- **Never pass a conditionally-empty argument to a native command.** PS 7 forwards `''` as a real `""` argument; this is the bug that caused the outage this work replaces. Build native-command arguments as arrays with every element validated non-empty.
- **Preserve file bytes.** The `.nuspec` files have **no BOM**; `tools/chocolateyinstall.ps1` files **have a UTF-8 BOM**. `core.autocrlf=true`, so working-tree files are CRLF. Only the intended value may change.
- **Nuspec `<version>` is addressed via XML XPath, never regex.** `fslogix.nuspec` contains `<dependency id="KB2919355" version="1.0.20160915" />`; a regex on `version` would corrupt it.
- **Push source:** `https://push.chocolatey.org`. **API key:** `$env:api_key`. The key must never appear in logs.
- **Exit code:** `0` when no package failed (including skipped / already-published), `1` when any package failed.
- **Tests are hermetic:** no network, no `choco`, no `git`.
- **Package version strings are used verbatim** as scraped. Never round-trip through `[version]` for output (`[version]'25.02'.ToString()` is `25.2`), only for comparison.

---

### Task 1: Nuspec read/write and version comparison

**Files:**
- Create: `lib/ChocoPkg.psm1`
- Create: `run-tests.ps1`
- Create: `tests/fixtures/sample.nuspec` (frozen copy of `fslogix/fslogix.nuspec`)
- Test: `tests/Nuspec.Tests.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces: `Get-NuspecVersion -Path <string> → string`, `Get-NuspecId -Path <string> → string`, `Set-NuspecVersion -Path <string> -Version <string>`, `Test-VersionIsNewer -Candidate <string> -Current <string> → bool`.

- [ ] **Step 1: Create the test bootstrap and fixture**

`run-tests.ps1`:

```powershell
[CmdletBinding()]
param([string] $Path = "$PSScriptRoot/tests")

$ErrorActionPreference = 'Stop'

function Get-Pester5 {
    Get-Module Pester -ListAvailable |
        Where-Object { $_.Version -ge [version]'5.0.0' } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

$pester = Get-Pester5
if (-not $pester) {
    Write-Host 'Pester 5 not found; installing to CurrentUser...'
    Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
    $pester = Get-Pester5
}
if (-not $pester) { throw 'Pester 5 could not be installed.' }

Import-Module $pester.Path -Force
Write-Host "Using Pester $($pester.Version)"

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

Freeze the fixture from the real package (it has no BOM, CRLF endings, and a `version` attribute on a dependency — all three properties the tests rely on):

```powershell
New-Item -ItemType Directory -Path tests/fixtures -Force | Out-Null
Copy-Item fslogix/fslogix.nuspec tests/fixtures/sample.nuspec
```

- [ ] **Step 2: Write the failing tests**

`tests/Nuspec.Tests.ps1`:

```powershell
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: FAIL — `lib/ChocoPkg.psm1` does not exist / commands not found.

- [ ] **Step 4: Implement**

Create `lib/ChocoPkg.psm1` with:

```powershell
Set-StrictMode -Version 3.0

function Get-NuspecXml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($resolved)
    $xml
}

function Get-NuspecVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $xml = Get-NuspecXml -Path $Path
    $node = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="version"]')
    if (-not $node) { throw "No <version> element found in '$Path'." }
    $node.InnerText
}

function Get-NuspecId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $xml = Get-NuspecXml -Path $Path
    $node = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="id"]')
    if (-not $node) { throw "No <id> element found in '$Path'." }
    $node.InnerText
}

function Set-NuspecVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Version
    )

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $xml = Get-NuspecXml -Path $resolved
    $node = $xml.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="version"]')
    if (-not $node) { throw "No <version> element found in '$resolved'." }
    $node.InnerText = $Version

    # XmlDocument.Save(string) writes a BOM; the nuspec files have none, so write
    # through an explicit writer to keep the file byte-identical apart from the version.
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $false
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::None
    $writer = [System.Xml.XmlWriter]::Create($resolved, $settings)
    try { $xml.Save($writer) } finally { $writer.Dispose() }
}

function Test-VersionIsNewer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Candidate,
        [Parameter(Mandatory)][string] $Current
    )

    $c = $null
    $u = $null
    if (-not [version]::TryParse($Candidate, [ref]$c)) { throw "Unparseable candidate version: '$Candidate'" }
    if (-not [version]::TryParse($Current, [ref]$u))   { throw "Unparseable current version: '$Current'" }
    $c -gt $u
}

Export-ModuleMember -Function Get-NuspecVersion, Get-NuspecId, Set-NuspecVersion, Test-VersionIsNewer
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: PASS — 9 tests.

- [ ] **Step 6: Commit**

```bash
git add run-tests.ps1 lib/ChocoPkg.psm1 tests/Nuspec.Tests.ps1 tests/fixtures/sample.nuspec
git commit -m "Add nuspec read/write and version comparison primitives"
```

---

### Task 2: File rewriting with encoding preservation

**Files:**
- Modify: `lib/ChocoPkg.psm1`
- Create: `tests/fixtures/sample-install.ps1` (frozen copy of `fslogix/tools/chocolateyinstall.ps1`)
- Test: `tests/PackageFile.Tests.ps1`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `Update-PackageFile -Path <string> -Replacements <hashtable>` (regex → replacement), `Get-DefaultReplacements -Url <string> -Checksum <string> → hashtable`.

**Critical detail:** `^` in the replacement patterns must match line starts, so the regex needs `RegexOptions::Multiline`. AU got this for free because it read files as a line array; reading the whole file as one string does not.

- [ ] **Step 1: Create the fixture**

```powershell
Copy-Item fslogix/tools/chocolateyinstall.ps1 tests/fixtures/sample-install.ps1
```

- [ ] **Step 2: Write the failing tests**

`tests/PackageFile.Tests.ps1`:

```powershell
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
            Should -Throw
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: FAIL — `Update-PackageFile` / `Get-DefaultReplacements` not found.

- [ ] **Step 4: Implement**

Add to `lib/ChocoPkg.psm1`:

```powershell
function Get-DefaultReplacements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Url,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Checksum
    )

    @{
        "(?i)(^\s*url\s*=\s*)('.*')"      = "`${1}'$Url'"
        "(?i)(^\s*checksum\s*=\s*)('.*')" = "`${1}'$Checksum'"
    }
}

function Update-PackageFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][hashtable] $Replacements
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: '$Path'" }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath

    $bytes = [System.IO.File]::ReadAllBytes($resolved)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [System.IO.File]::ReadAllText($resolved)

    foreach ($pattern in $Replacements.Keys) {
        $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if (-not $regex.IsMatch($text)) {
            throw "Pattern matched nothing in '$resolved': $pattern"
        }
        $text = $regex.Replace($text, $Replacements[$pattern])
    }

    $encoding = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($resolved, $text, $encoding)
}
```

Add `Get-DefaultReplacements, Update-PackageFile` to the `Export-ModuleMember` list.

- [ ] **Step 5: Run tests to verify they pass**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: PASS — 16 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/ChocoPkg.psm1 tests/PackageFile.Tests.ps1 tests/fixtures/sample-install.ps1
git commit -m "Add package file rewriting with encoding preservation"
```

---

### Task 3: Checksum, pack, and push

**Files:**
- Modify: `lib/ChocoPkg.psm1`
- Test: `tests/Publish.Tests.ps1`

**Interfaces:**
- Consumes: `Get-NuspecId`, `Get-NuspecVersion` (Task 1).
- Produces: `Get-UrlChecksum -Url <string> [-WebRequestArgs <hashtable>] → string` (lowercase sha256), `Clear-UrlChecksumCache`, `Invoke-ChocoPack -NuspecPath <string> -OutputDirectory <string> → string` (nupkg path), `Get-ChocoPushArgs -NupkgPath <string> -Source <string> -ApiKey <string> → string[]`, `Test-DuplicateVersionOutput -Output <string> → bool`, `Invoke-ChocoPush -NupkgPath <string> -Source <string> -ApiKey <string> → [pscustomobject]@{ Outcome; Output }` where `Outcome` is `'pushed'`, `'already published'`, or `'failed'`, `Invoke-WithRetry -ScriptBlock <scriptblock> [-Attempts <int>] [-DelaySeconds <int>] → the scriptblock's output`.

Per the spec, `Invoke-ChocoPack` and the network half of `Invoke-ChocoPush` are **not** unit-tested (tests stay hermetic); they are verified by the canary run in Task 7. The pure argument-building and output-classification functions carry the tests, because those are where the outage lived.

- [ ] **Step 1: Write the failing tests**

`tests/Publish.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: FAIL — `Get-ChocoPushArgs` and friends not found.

- [ ] **Step 3: Implement**

Add to `lib/ChocoPkg.psm1`:

```powershell
$script:ChecksumCache = @{}

function Clear-UrlChecksumCache {
    [CmdletBinding()]
    param()
    $script:ChecksumCache = @{}
}

function Get-UrlChecksum {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Url,
        [hashtable] $WebRequestArgs = @{}
    )

    if ($script:ChecksumCache.ContainsKey($Url)) { return $script:ChecksumCache[$Url] }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    try {
        Invoke-WebRequest -Uri $Url -OutFile $temp -MaximumRetryCount 3 -RetryIntervalSec 5 @WebRequestArgs
        $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    $script:ChecksumCache[$Url] = $hash
    $hash
}

function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [int] $Attempts = 3,
        [int] $DelaySeconds = 15
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try { return & $ScriptBlock }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Host "  attempt $i of $Attempts failed: $($_.Exception.Message)"
            if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
        }
    }
}

function Invoke-ChocoPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $NuspecPath,
        [Parameter(Mandatory)][string] $OutputDirectory
    )

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $resolvedNuspec = (Resolve-Path -LiteralPath $NuspecPath).ProviderPath
    $resolvedOut = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath

    $packArgs = @('pack', $resolvedNuspec, '--output-directory', $resolvedOut, '--limit-output')
    & choco @packArgs
    if ($LASTEXITCODE -ne 0) { throw "choco pack failed with exit code $LASTEXITCODE" }

    $id = Get-NuspecId -Path $resolvedNuspec
    $version = Get-NuspecVersion -Path $resolvedNuspec
    $expected = Join-Path $resolvedOut "$id.$version.nupkg"
    if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) {
        throw "choco pack reported success but '$expected' does not exist."
    }
    $expected
}

function Get-ChocoPushArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $NupkgPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Source,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ApiKey
    )

    foreach ($pair in @(@('NupkgPath', $NupkgPath), @('Source', $Source), @('ApiKey', $ApiKey))) {
        if ([string]::IsNullOrWhiteSpace($pair[1])) { throw "$($pair[0]) must not be empty." }
    }

    @('push', $NupkgPath, '--source', $Source, '--api-key', $ApiKey, '--limit-output')
}

function Test-DuplicateVersionOutput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Output)

    [bool]($Output -match '(?i)already exists|\(409\)')
}

function Invoke-ChocoPush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $NupkgPath,
        [string] $Source = 'https://push.chocolatey.org',
        [string] $ApiKey = $env:api_key
    )

    $pushArgs = Get-ChocoPushArgs -NupkgPath $NupkgPath -Source $Source -ApiKey $ApiKey
    $raw = (& choco @pushArgs 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $safe = $raw.Replace($ApiKey, '***')

    $outcome =
        if ($code -eq 0) { 'pushed' }
        elseif (Test-DuplicateVersionOutput -Output $safe) { 'already published' }
        else { 'failed' }

    [pscustomobject]@{ Outcome = $outcome; Output = $safe }
}
```

Add `Get-UrlChecksum, Clear-UrlChecksumCache, Invoke-WithRetry, Invoke-ChocoPack, Get-ChocoPushArgs, Test-DuplicateVersionOutput, Invoke-ChocoPush` to `Export-ModuleMember`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: PASS — 27 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ChocoPkg.psm1 tests/Publish.Tests.ps1
git commit -m "Add checksum, pack and push primitives with argument validation"
```

---

### Task 4: Upstream detectors

**Files:**
- Create: `lib/Sources.psm1`
- Create: `tests/fixtures/fslogix-release-notes.html`
- Create: `tests/fixtures/github-latest-release.json`
- Test: `tests/Sources.Tests.ps1`

**Interfaces:**
- Consumes: nothing (detectors return `Version`/`Url` only; the checksum is taken by each `update.ps1` via `Get-UrlChecksum`, which keeps `Sources.psm1` free of any dependency on `ChocoPkg.psm1` while still downloading the shared fslogix zip only once per run through that function's cache).
- Produces: `Select-FsLogixReleaseFromHtml -Html <string> → [pscustomobject]@{ Version; Url }`, `Get-FsLogixRelease → [pscustomobject]@{ Version; Url }`, `Select-MsiAssetFromRelease -Release <object> → [pscustomobject]@{ Version; Url }`, `Get-GitHubLatestRelease -Repository <string> → [pscustomobject]@{ Version; Url }`.

Each detector splits into a network fetch and a pure parser. Only the parsers are unit-tested; a live check in Step 5 confirms the fetch half against the real pages.

- [ ] **Step 1: Create the fixtures**

`tests/fixtures/fslogix-release-notes.html` — mirrors the real page's shape: external links whose text carries a parenthesized version, plus decoys (an internal link, and an external link with no version) that must be ignored.

```html
<html><body>
<h2>FSLogix 3.26.826.17182</h2>
<p><a href="/en-us/fslogix/overview" data-linktype="relative-path">Overview (3.99.0.0)</a></p>
<p><a href="https://download.microsoft.com/download/aaa/FSLogix_26.08.zip" data-linktype="external">Download FSLogix Apps (3.26.826.17182)</a></p>
<p><a href="https://download.microsoft.com/download/bbb/FSLogix_25.02.zip" data-linktype="external">Download FSLogix Apps (3.25.202.4223)</a></p>
<p><a href="https://example.test/no-version" data-linktype="external">Release notes archive</a></p>
</body></html>
```

`tests/fixtures/github-latest-release.json` — trimmed to the fields the parser reads, including a non-MSI asset that must be skipped:

```json
{
  "tag_name": "v7.1912.6",
  "assets": [
    { "browser_download_url": "https://github.com/EUCweb/BIS-F/releases/download/7.1912.6/source.zip" },
    { "browser_download_url": "https://github.com/EUCweb/BIS-F/releases/download/7.1912.6/setup-BIS-F-7.1912.6.11041.MSI" }
  ]
}
```

- [ ] **Step 2: Write the failing tests**

`tests/Sources.Tests.ps1`:

```powershell
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: FAIL — `lib/Sources.psm1` does not exist.

- [ ] **Step 4: Implement**

Create `lib/Sources.psm1`:

```powershell
Set-StrictMode -Version 3.0

function Select-FsLogixReleaseFromHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Html)

    $anchors = [regex]::Matches(
        $Html,
        '<a\b[^>]*>.*?</a>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $found = foreach ($anchor in $anchors) {
        $tag = $anchor.Value
        if ($tag -notmatch 'data-linktype\s*=\s*"external"') { continue }

        if ($tag -notmatch '\((\d+(?:\.\d+){1,3})\)') { continue }
        $versionText = $Matches[1]

        if ($tag -notmatch 'href\s*=\s*"([^"]+)"') { continue }
        $url = $Matches[1]

        $parsed = $null
        if (-not [version]::TryParse($versionText, [ref]$parsed)) { continue }

        [pscustomobject]@{ Version = $versionText; Url = $url; Sort = $parsed }
    }

    if (-not $found) { throw 'Found no external link with a parseable version on the FSLogix release notes page.' }

    $best = $found | Sort-Object Sort -Descending | Select-Object -First 1
    [pscustomobject]@{ Version = $best.Version; Url = $best.Url }
}

function Get-FsLogixRelease {
    [CmdletBinding()]
    param([string] $Uri = 'https://learn.microsoft.com/en-us/fslogix/overview-release-notes')

    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -MaximumRetryCount 3 -RetryIntervalSec 5
    Select-FsLogixReleaseFromHtml -Html $response.Content
}

function Select-MsiAssetFromRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Release)

    $msi = $Release.assets | Where-Object { $_.browser_download_url -match '\.msi$' } | Select-Object -First 1
    if (-not $msi) { throw 'GitHub latest release does not contain an MSI asset.' }

    [pscustomobject]@{
        Version = ([string]$Release.tag_name).TrimStart('v')
        Url     = $msi.browser_download_url
    }
}

function Get-GitHubLatestRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Repository)

    $headers = @{
        'User-Agent' = 'chocolatey-package-update'
        'Accept'     = 'application/vnd.github+json'
    }
    # Runner IPs are shared and heavily rate-limited unauthenticated.
    if ($env:github_api_key) { $headers['Authorization'] = "Bearer $($env:github_api_key)" }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" `
        -Headers $headers -MaximumRetryCount 3 -RetryIntervalSec 5
    Select-MsiAssetFromRelease -Release $release
}

Export-ModuleMember -Function Select-FsLogixReleaseFromHtml, Get-FsLogixRelease, Select-MsiAssetFromRelease, Get-GitHubLatestRelease
```

- [ ] **Step 5: Run tests, then check the fetch half against the live pages**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: PASS — 33 tests.

The unit tests prove the parsers; this confirms the handcrafted fixtures actually match reality:

```powershell
pwsh -NoProfile -c "Import-Module ./lib/Sources.psm1 -Force; Get-FsLogixRelease | Format-List; Get-GitHubLatestRelease -Repository 'EUCweb/BIS-F' | Format-List"
```

Expected: FSLogix reports `Version = 3.26.826.17182` with a `download.microsoft.com` zip URL; BIS-F reports `Version = 7.1912.6` with the `.MSI` asset URL. **If the FSLogix version comes back lower than `3.26.826.17182`, or either call throws, stop and report** — the page structure has changed and the fixture needs recapturing from the live HTML.

- [ ] **Step 6: Commit**

```bash
git add lib/Sources.psm1 tests/Sources.Tests.ps1 tests/fixtures/fslogix-release-notes.html tests/fixtures/github-latest-release.json
git commit -m "Add GitHub and FSLogix release detectors with testable parsers"
```

---

### Task 5: Package discovery and the per-package orchestrator

**Files:**
- Modify: `lib/ChocoPkg.psm1`
- Test: `tests/PackageUpdate.Tests.ps1`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces:
  - `Get-ChocoPackage -Root <string> → [pscustomobject]@{ Name; Path; NuspecPath; UpdateScript }[]` sorted by `Name`.
  - `Get-OptionalProperty -InputObject <object> -Name <string> [-Default <object>] → object`.
  - `Invoke-PackageUpdate -Package <object> -ArtifactDirectory <string> [-Source <string>] [-ApiKey <string>] [-DetectAttempts <int>] [-DetectDelaySeconds <int>] [-Force] [-CheckOnly] [-NoPush] → [pscustomobject]@{ Name; CurrentVersion; DetectedVersion; Outcome; ChangedFiles; Error; Output }` where `Outcome` is one of `'no change'`, `'checked'`, `'packed'`, `'pushed'`, `'already published'`, `'failed'`.

`Set-StrictMode -Version 3.0` throws on references to non-existent properties, so the optional contract keys (`Replace`, `InstallScript`) must be read through `Get-OptionalProperty`, never with direct dotted access.

- [ ] **Step 1: Write the failing tests**

`tests/PackageUpdate.Tests.ps1`:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../lib/ChocoPkg.psm1" -Force
    $script:NuspecFixture  = Join-Path $PSScriptRoot 'fixtures/sample.nuspec'
    $script:InstallFixture = Join-Path $PSScriptRoot 'fixtures/sample-install.ps1'
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: FAIL — `Get-ChocoPackage` / `Invoke-PackageUpdate` not found.

- [ ] **Step 3: Implement**

Add to `lib/ChocoPkg.psm1`:

```powershell
function Get-ChocoPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root)

    Get-ChildItem -LiteralPath $Root -Directory | ForEach-Object {
        $updateScript = Join-Path $_.FullName 'update.ps1'
        $nuspec = Get-ChildItem -LiteralPath $_.FullName -Filter '*.nuspec' -File | Select-Object -First 1
        if ((Test-Path -LiteralPath $updateScript -PathType Leaf) -and $nuspec) {
            [pscustomobject]@{
                Name         = $_.Name
                Path         = $_.FullName
                NuspecPath   = $nuspec.FullName
                UpdateScript = $updateScript
            }
        }
    } | Sort-Object Name
}

function Get-OptionalProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string] $Name,
        $Default = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value) { $property.Value } else { $Default }
}

function Invoke-PackageUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Package,
        [Parameter(Mandatory)][string] $ArtifactDirectory,
        [string] $Source = 'https://push.chocolatey.org',
        [string] $ApiKey = $env:api_key,
        [int]    $DetectAttempts = 3,
        [int]    $DetectDelaySeconds = 15,
        [switch] $Force,
        [switch] $CheckOnly,
        [switch] $NoPush
    )

    $result = [pscustomobject]@{
        Name            = $Package.Name
        CurrentVersion  = $null
        DetectedVersion = $null
        Outcome         = 'failed'
        ChangedFiles    = @()
        Error           = $null
        Output          = ''
    }

    try {
        $result.CurrentVersion = Get-NuspecVersion -Path $Package.NuspecPath

        $detected = Invoke-WithRetry -ScriptBlock { & $Package.UpdateScript } -Attempts $DetectAttempts -DelaySeconds $DetectDelaySeconds | Select-Object -Last 1
        if (-not $detected) { throw "'$($Package.Name)' update script returned nothing." }

        foreach ($required in @('Version', 'Url', 'Checksum')) {
            if ([string]::IsNullOrWhiteSpace((Get-OptionalProperty -InputObject $detected -Name $required))) {
                throw "'$($Package.Name)' update script did not return a non-empty '$required'."
            }
        }
        $result.DetectedVersion = $detected.Version

        if (-not $Force -and -not (Test-VersionIsNewer -Candidate $detected.Version -Current $result.CurrentVersion)) {
            $result.Outcome = 'no change'
            return $result
        }

        if ($CheckOnly) {
            $result.Outcome = 'checked'
            return $result
        }

        $installRelative = Get-OptionalProperty -InputObject $detected -Name 'InstallScript' -Default 'tools\chocolateyinstall.ps1'
        $installPath = Join-Path $Package.Path $installRelative
        $replacements = Get-OptionalProperty -InputObject $detected -Name 'Replace' `
            -Default (Get-DefaultReplacements -Url $detected.Url -Checksum $detected.Checksum)

        Update-PackageFile -Path $installPath -Replacements $replacements
        Set-NuspecVersion -Path $Package.NuspecPath -Version $detected.Version
        $result.ChangedFiles = @(
            (Resolve-Path -LiteralPath $installPath).ProviderPath
            (Resolve-Path -LiteralPath $Package.NuspecPath).ProviderPath
        )

        $nupkg = Invoke-ChocoPack -NuspecPath $Package.NuspecPath -OutputDirectory $ArtifactDirectory

        if ($NoPush) {
            $result.Outcome = 'packed'
            return $result
        }

        $push = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $push = Invoke-ChocoPush -NupkgPath $nupkg -Source $Source -ApiKey $ApiKey
            if ($push.Outcome -ne 'failed') { break }
            if ($attempt -lt 3) {
                Write-Host "  push attempt $attempt failed; retrying"
                Start-Sleep -Seconds 15
            }
        }

        $result.Outcome = $push.Outcome
        $result.Output = $push.Output
        if ($push.Outcome -eq 'failed') { $result.Error = "choco push failed: $($push.Output)" }
    }
    catch {
        $result.Outcome = 'failed'
        $result.Error = $_
    }

    $result
}
```

Add `Get-ChocoPackage, Get-OptionalProperty, Invoke-PackageUpdate` to `Export-ModuleMember`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: PASS — 43 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ChocoPkg.psm1 tests/PackageUpdate.Tests.ps1
git commit -m "Add package discovery and per-package update orchestrator"
```

---

### Task 6: The runner

**Files:**
- Create: `update-all.ps1`
- Create: `.gitignore`

**Interfaces:**
- Consumes: `Get-ChocoPackage`, `Invoke-PackageUpdate` (Task 5); `lib/Sources.psm1` detectors (Task 4), imported globally so each `update.ps1` can call them.
- Produces: the CLI `update-all.ps1 [-Name <string[]>] [-Force] [-CheckOnly] [-NoPush] [-NoCommit] [-Root <string>]`, exit `0`/`1`.

- [ ] **Step 1: Create `.gitignore`**

```
artifacts/
update_vars.ps1
*.nupkg
```

- [ ] **Step 2: Implement the runner**

`update-all.ps1`:

```powershell
[CmdletBinding()]
param(
    [string[]] $Name,
    [switch]   $Force,
    [switch]   $CheckOnly,
    [switch]   $NoPush,
    [switch]   $NoCommit,
    [string]   $Root = $PSScriptRoot
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$varsFile = Join-Path $PSScriptRoot 'update_vars.ps1'
if (Test-Path -LiteralPath $varsFile) { . $varsFile }

Import-Module (Join-Path $PSScriptRoot 'lib/ChocoPkg.psm1') -Force -Global
Import-Module (Join-Path $PSScriptRoot 'lib/Sources.psm1') -Force -Global

$artifactDirectory = Join-Path $Root 'artifacts'
$packages = @(Get-ChocoPackage -Root $Root)
if ($Name) { $packages = @($packages | Where-Object { $_.Name -in $Name }) }
if (-not $packages) { throw "No packages found to update (root '$Root', filter '$($Name -join ', ')')." }

$mode = if ($CheckOnly) { 'check only' } elseif ($NoPush) { 'no push' } else { 'full' }
Write-Host "Updating $($packages.Count) package(s), mode: $mode"
if ($Force) { Write-Host 'FORCE enabled: packages update even when the detected version is not newer.' }

$results = foreach ($package in $packages) {
    Write-Host ''
    Write-Host ('-' * 60)
    Write-Host "PACKAGE: $($package.Name)"

    $splat = @{
        Package           = $package
        ArtifactDirectory = $artifactDirectory
        Force             = $Force
        CheckOnly         = $CheckOnly
        NoPush            = $NoPush
    }
    $result = Invoke-PackageUpdate @splat

    Write-Host "  current:  $($result.CurrentVersion)"
    Write-Host "  detected: $($result.DetectedVersion)"
    Write-Host "  outcome:  $($result.Outcome)"
    if ($result.Error) { Write-Host "  error:    $($result.Error)" }
    $result
}

$results = @($results)
$committable = @($results | Where-Object { $_.Outcome -in @('pushed', 'already published', 'packed') -and $_.ChangedFiles })

if (-not $NoCommit -and -not $CheckOnly -and $committable) {
    # Stage only the files of packages that got as far as a successful pack/push.
    # A failed package has already had its files rewritten on disk; 'git add -A'
    # would record a version bump for something that was never published.
    $paths = $committable.ChangedFiles
    git add -- @paths
    if ($LASTEXITCODE -ne 0) { throw "git add failed with exit code $LASTEXITCODE" }

    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Nothing staged; skipping commit.'
    }
    else {
        $summary = ($committable | ForEach-Object { "$($_.Name) $($_.DetectedVersion)" }) -join ', '
        git commit -m "Update: $summary [skip ci]"
        if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE" }
        git push
        if ($LASTEXITCODE -ne 0) { throw "git push failed with exit code $LASTEXITCODE" }
    }
}

Write-Host ''
Write-Host ('=' * 60)
$results | Select-Object Name, CurrentVersion, DetectedVersion, Outcome | Format-Table -AutoSize | Out-String | Write-Host

$counts = $results | Group-Object Outcome | ForEach-Object { "$($_.Count) $($_.Name)" }
Write-Host ($counts -join ', ')

$failed = @($results | Where-Object { $_.Outcome -eq 'failed' })
if ($failed) {
    Write-Host ''
    Write-Host "FAILED: $($failed.Name -join ', ')"
    exit 1
}
exit 0
```

- [ ] **Step 3: Verify the runner wires up, without touching any files**

Run: `pwsh -NoProfile -File ./update-all.ps1 -CheckOnly`
Expected: it discovers `bis-f`, `fslogix`, `fslogix-rule`, and each fails with an error about the update script (they are still AU scripts at this point) — proving discovery, isolation, the summary table, and `exit 1`. Confirm `fslogix-java` is absent from the table.

Run: `pwsh -NoProfile -c "./update-all.ps1 -CheckOnly; \$LASTEXITCODE"`
Expected: prints `1`.

- [ ] **Step 4: Commit**

```bash
git add update-all.ps1 .gitignore
git commit -m "Add update runner with per-package isolation and non-zero exit on failure"
```

---

### Task 7: Port bis-f (the canary)

**Files:**
- Modify: `bis-f/update.ps1`

**Interfaces:**
- Consumes: `Get-GitHubLatestRelease` (Task 4), `Get-UrlChecksum` (Task 3).
- Produces: a package script conforming to the contract.

`bis-f` is already at its latest version, so this task exercises the whole detect-and-compare path with no possibility of a publish.

- [ ] **Step 1: Replace `bis-f/update.ps1`**

```powershell
[CmdletBinding()]
param()

$release = Get-GitHubLatestRelease -Repository 'EUCweb/BIS-F'

[pscustomobject]@{
    Version  = $release.Version
    Url      = $release.Url
    Checksum = Get-UrlChecksum -Url $release.Url
}
```

- [ ] **Step 2: Run the canary**

Run: `pwsh -NoProfile -File ./update-all.ps1 -Name bis-f -CheckOnly`
Expected: `current: 7.1912.6`, `detected: 7.1912.6`, `outcome: no change`, exit `0`. Nothing on disk changes — confirm with `git status --porcelain` (empty).

- [ ] **Step 3: Exercise the full write/pack path without publishing**

Run: `pwsh -NoProfile -File ./update-all.ps1 -Name bis-f -Force -NoPush -NoCommit`
Expected: `outcome: packed`. This proves `Update-PackageFile`, `Set-NuspecVersion` and `Invoke-ChocoPack` work against a real package with real `choco`. Verify the diff is exactly the checksum/url values re-written to the same values (likely an empty diff) and that `artifacts/bis-f.7.1912.6.nupkg` exists.

Then discard any incidental changes: `git checkout -- bis-f/`

- [ ] **Step 4: Commit**

```bash
git add bis-f/update.ps1
git commit -m "Port bis-f to the new update contract"
```

---

### Task 8: Port fslogix and fslogix-rule

**Files:**
- Modify: `fslogix/update.ps1`
- Modify: `fslogix-rule/update.ps1`

**Interfaces:**
- Consumes: `Get-FsLogixRelease` (Task 4), `Get-UrlChecksum` (Task 3).
- Produces: two package scripts conforming to the contract.

Both packages track the same upstream zip. The `Get-UrlChecksum` cache means it downloads once per run rather than twice, which is why the two scripts are identical.

- [ ] **Step 1: Replace `fslogix/update.ps1` and `fslogix-rule/update.ps1`**

Identical content for both files:

```powershell
[CmdletBinding()]
param()

$release = Get-FsLogixRelease

# The Microsoft download host needs these; without them the request is rejected.
$webRequestArgs = @{
    SkipCertificateCheck = $true
    SkipHeaderValidation = $true
}

[pscustomobject]@{
    Version  = $release.Version
    Url      = $release.Url
    Checksum = Get-UrlChecksum -Url $release.Url -WebRequestArgs $webRequestArgs
}
```

- [ ] **Step 2: Check detection for all three packages**

Run: `pwsh -NoProfile -File ./update-all.ps1 -CheckOnly`
Expected table:

```
Name         CurrentVersion DetectedVersion  Outcome
----         -------------- ---------------  -------
bis-f        7.1912.6       7.1912.6         no change
fslogix      3.25.202.4223  3.26.826.17182   checked
fslogix-rule 3.25.202.4223  3.26.826.17182   checked
```

Exit `0`, and `git status --porcelain` is empty. **If either fslogix package reports a different detected version, stop and report.**

- [ ] **Step 3: Commit**

```bash
git add fslogix/update.ps1 fslogix-rule/update.ps1
git commit -m "Port fslogix and fslogix-rule to the new update contract"
```

---

### Task 9: Swap the workflow

**Files:**
- Delete: `.github/workflows/au-update.yml`
- Create: `.github/workflows/package-update.yml`

**Interfaces:**
- Consumes: `update-all.ps1` (Task 6), `run-tests.ps1` (Task 1).
- Produces: CI that runs tests on every trigger, checks on PRs, and publishes on schedule/dispatch.

Workflow inputs reach PowerShell through `env:`, never string-interpolated into the script body — `${{ inputs.packages }}` inlined into a `run:` block would be a script-injection vector.

- [ ] **Step 1: Create `.github/workflows/package-update.yml`**

```yaml
name: Package Update

on:
  push:
    branches:
      - master
  pull_request:
    branches:
      - master
  schedule:
    - cron: "0 4 * * *"
  workflow_dispatch:
    inputs:
      mode:
        description: "Run mode"
        type: choice
        required: true
        default: check
        options:
          - check
          - full
      packages:
        description: "Optional space-separated package names (e.g. fslogix bis-f)"
        required: false
        type: string
      force:
        description: "Update even when the detected version is not newer"
        required: false
        type: boolean
        default: false

permissions:
  contents: write

concurrency:
  group: package-update-${{ github.ref }}
  cancel-in-progress: false

env:
  api_key: ${{ secrets.CHOCOLATEY_API_KEY }}
  github_api_key: ${{ github.token }}

jobs:
  update:
    runs-on: windows-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: Build environment info
        shell: pwsh
        run: |
          $PSVersionTable | Format-List
          choco --version
          (Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version

      - name: Run tests
        shell: pwsh
        run: ./run-tests.ps1

      - name: Configure git identity
        shell: pwsh
        run: |
          git config user.name 'github-actions[bot]'
          git config user.email 'github-actions[bot]@users.noreply.github.com'

      - name: Update packages
        shell: pwsh
        env:
          GH_EVENT_NAME: ${{ github.event_name }}
          GH_MODE: ${{ inputs.mode }}
          GH_PACKAGES: ${{ inputs.packages }}
          GH_FORCE: ${{ inputs.force }}
        run: |
          $splat = @{}

          if ($Env:GH_EVENT_NAME -eq 'pull_request') {
            Write-Host 'Pull request: check-only, nothing is written or published.'
            $splat.CheckOnly = $true
          }
          elseif ($Env:GH_EVENT_NAME -eq 'workflow_dispatch') {
            if ($Env:GH_MODE -ne 'full') { $splat.CheckOnly = $true }
            if ($Env:GH_FORCE -eq 'true') { $splat.Force = $true }
            if (-not [string]::IsNullOrWhiteSpace($Env:GH_PACKAGES)) {
              $splat.Name = $Env:GH_PACKAGES.Trim() -split '\s+'
            }
          }

          ./update-all.ps1 @splat

      - name: Upload built packages
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: packages-${{ github.run_number }}
          if-no-files-found: ignore
          retention-days: 7
          path: artifacts/*.nupkg
```

- [ ] **Step 2: Delete the AU workflow**

```bash
git rm .github/workflows/au-update.yml
```

- [ ] **Step 3: Commit and verify on a branch**

```bash
git add .github/workflows/package-update.yml
git commit -m "Replace AU workflow with package-update workflow"
git push -u origin replace-au-engine
gh pr create --fill --base master
```

Expected on the PR run: the Pester suite passes, then `update-all.ps1 -CheckOnly` reports `no change` for `bis-f` and `checked` for both fslogix packages, exit `0`, with nothing published and no commit. Watch it with:

```bash
gh run watch $(gh run list --workflow=package-update.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

- [ ] **Step 4: Verify a dispatch check run**

After merging, run the workflow manually with `mode: check`.
Expected: identical detection output; nothing published.

---

### Task 10: Resync the repository with what is already published

**Files:**
- Modify: `fslogix/fslogix.nuspec`, `fslogix/tools/chocolateyinstall.ps1`
- Modify: `fslogix-rule/fslogix-rule.nuspec`, `fslogix-rule/tools/chocolateyinstall.ps1`

`3.26.826.17182` was pushed to Chocolatey by hand, so the repository is behind the feed. This resyncs it using the new code, publishing nothing.

**Stop and ask the user before running this task** — it commits to `master`.

- [ ] **Step 1: Run the resync**

Run: `pwsh -NoProfile -File ./update-all.ps1 -NoPush`
Expected: `bis-f` reports `no change`; both fslogix packages report `packed`; one commit is created and pushed containing exactly four changed files.

- [ ] **Step 2: Verify the diff is only version, url and checksum**

```bash
git show --stat HEAD
git show HEAD
```

Expected: `<version>` set to `3.26.826.17182` in both nuspecs (with the `KB2919355` dependency `version` attribute untouched), and `url`/`checksum` updated in both install scripts. No whitespace-only churn, no BOM changes. Verify with:

```bash
git show HEAD --numstat
```

Expected: 2 insertions / 2 deletions per file, 8 total.

- [ ] **Step 3: Confirm the next run is quiet**

Run: `pwsh -NoProfile -File ./update-all.ps1 -CheckOnly`
Expected: all three packages report `no change`, exit `0`.

---

### Task 11: Remove AU and update the README

**Files:**
- Delete: `update_all.ps1`, `test-all.ps1`, `plugins/RunInfoSafe.ps1`, `appveyor.yml`
- Modify: `README.md`

- [ ] **Step 1: Delete the AU-era files**

```bash
git rm update_all.ps1 test-all.ps1 plugins/RunInfoSafe.ps1 appveyor.yml
```

- [ ] **Step 2: Confirm nothing still references AU**

```bash
grep -rniE "\bau\b|updateall|lsau|Push-Package|majkinetor" --include="*.ps1" --include="*.yml" --include="*.md" . | grep -v "^./docs/superpowers/"
```

Expected: no hits outside `docs/superpowers/` (the spec and this plan legitimately discuss AU).

- [ ] **Step 3: Rewrite the README sections**

Replace the "Repository Structure", "Automation" and "Run Updates Locally" sections with:

```markdown
## Repository Structure

- `bis-f/`, `fslogix/`, `fslogix-rule/`: package files and update script per package.
- `fslogix-java/`: retired; not picked up by the updater.
- `lib/ChocoPkg.psm1`: nuspec/file rewriting, checksum, pack and push primitives.
- `lib/Sources.psm1`: upstream release detectors.
- `update-all.ps1`: the update runner.
- `run-tests.ps1`: runs the Pester suite in `tests/`.

Each package's `update.ps1` only *detects* a release and returns
`@{ Version; Url; Checksum }`. The engine compares against the nuspec, rewrites
`tools/chocolateyinstall.ps1` and the nuspec version, packs, pushes, and commits.

## Automation

`.github/workflows/package-update.yml` runs the Pester suite on every trigger,
then:

- **pull request** — `update-all.ps1 -CheckOnly` (detects only; writes and
  publishes nothing).
- **schedule (04:00 UTC) / push to master** — full run: bump, pack, push, commit.
- **workflow_dispatch** — `mode: check` or `full`, with optional package names
  and a force switch.

A run that fails to publish something it should exits non-zero and fails the job.

## Run Updates Locally

Requires PowerShell 7 and the Chocolatey CLI.

```powershell
# Run the tests
./run-tests.ps1

# See what would change; writes nothing
./update-all.ps1 -CheckOnly

# One package only
./update-all.ps1 -Name fslogix -CheckOnly

# Bump, pack and commit without publishing
./update-all.ps1 -NoPush

# Full run (needs $Env:api_key, or an api_key assignment in update_vars.ps1)
./update-all.ps1
```
```

Also update the intro line, which currently says the repo "contains Automated Update (AU) scripts".

- [ ] **Step 4: Verify the suite and a check run still pass**

Run: `pwsh -NoProfile -File ./run-tests.ps1`
Expected: PASS — 43 tests.

Run: `pwsh -NoProfile -File ./update-all.ps1 -CheckOnly`
Expected: three packages, all `no change`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Remove AU scripts and document the new update engine"
```

---

## Notes for the executor

- **`Export-ModuleMember` accumulates.** Each task adds functions to `lib/ChocoPkg.psm1`; keep one `Export-ModuleMember` call at the end of the file listing every public function. By Task 5 it should read: `Get-NuspecVersion, Get-NuspecId, Set-NuspecVersion, Test-VersionIsNewer, Get-DefaultReplacements, Update-PackageFile, Get-UrlChecksum, Clear-UrlChecksumCache, Invoke-WithRetry, Invoke-ChocoPack, Get-ChocoPushArgs, Test-DuplicateVersionOutput, Invoke-ChocoPush, Get-ChocoPackage, Get-OptionalProperty, Invoke-PackageUpdate`. Internal helper `Get-NuspecXml` stays unexported.
- **Pester 5 is required** and the machine may only have 3.4.0; `run-tests.ps1` installs it on first run.
- **Mocking module-internal calls** needs `-ModuleName ChocoPkg`, because `Invoke-PackageUpdate` calls its siblings from inside the module's own scope.
- **Do not run Task 10 without asking.** It commits and pushes to `master`.
- **`$args` is an automatic variable** — the code deliberately uses `$pushArgs` / `$packArgs`.
