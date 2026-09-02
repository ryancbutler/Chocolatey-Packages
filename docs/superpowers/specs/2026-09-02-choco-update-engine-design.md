# Replacing AU with a purpose-built update engine

Date: 2026-09-02
Status: approved (design)

## Problem

This repository maintains three active Chocolatey packages (`bis-f`, `fslogix`,
`fslogix-rule`) using the [AU module](https://github.com/majkinetor/au). AU was
written for Windows PowerShell 5.1, and running it under PowerShell 7 has
produced two distinct silent-publish failures:

1. AU's built-in `RunInfo` plugin deep-clones `$Info.Options` with
   `BinaryFormatter`, which is disabled in .NET 8 and removed in .NET 9. Worked
   around by `plugins/RunInfoSafe.ps1`.
2. AU's `Push-Package` builds its `choco push` invocation with a conditionally
   empty argument (`$force_push = ''`). Windows PowerShell 5.1 silently drops
   empty arguments to native commands; PowerShell 7 passes them as a real `""`.
   Chocolatey joins its positional arguments, so the package path arrived as
   `'fslogix.3.26.826.17182.nupkg '` — with a trailing space — and was rejected
   as "File specified is either not found or not a .nupkg file".

Failure 2 made the 2026-09-02 runs report **success** while publishing nothing:
`0 updated, 0 pushed` with `2 errors`, and a green build. The version bumps were
never committed either, because AU's Git plugin skips when no package is marked
updated.

Both failures share a root cause beyond the specific bugs: AU's architecture
(magic `$Latest` globals, `global:au_*` hook functions, `Start-Job` fan-out with
cross-process serialization, plugin indirection) is 5.1-era machinery whose
failure modes are invisible from this repository. With three packages and two
detection patterns, that machinery costs more than it provides.

## Goals

- Detect upstream releases, bump package files, pack, and push — under
  PowerShell 7, with no AU dependency.
- Fail loudly. A run that does not publish what it should must exit non-zero.
- Make the publish-critical logic unit-testable without network, `choco`, or git.
- Keep the repository in sync with what is published on the community feed.

## Non-goals

Deliberately dropped, having been weighed and rejected:

- **Per-package git tags and GitHub releases** (AU's `GitReleases` plugin). Tags
  exist historically through `fslogix-rule-3.26.126.19110`; not being recreated.
- **`choco install` smoke test before push** (AU's `Test-Package`,
  `test-all.ps1`).
- **Markdown run reports and gist upload** (`Update-AUPackages.md`,
  `Update-History.md`). Gist was already disabled via `au_skip_gist=true` and the
  reports were never committed.
- **Mail notifications**, **parallel execution** (three packages run sequentially),
  and the **`[AU ...]` / `[PUSH ...]` commit-message parsing** in the workflow.
- **Separate 64-bit URL/checksum fields.** No package uses them today; `fslogix`
  selects `file`/`file64` from inside the extracted zip. Add when a package needs it.

## Architecture

```
lib/ChocoPkg.psm1        primitives + per-package orchestrator
lib/Sources.psm1         upstream detectors
update-all.ps1           runner: discover, loop, summarize, commit, exit code
tests/*.Tests.ps1        Pester
tests/fixtures/          captured nuspec, install script, MS Learn HTML, GitHub JSON
<pkg>/update.ps1         detection only
```

**Package discovery**: a directory is a package if it contains both a `*.nuspec`
and an `update.ps1`. This excludes the retired `fslogix-java` (which has
`update.ps1.old`) with no exclusion list to maintain.

### Package contract

`<pkg>/update.ps1` detects and returns. It never writes files, packs, or pushes.

```powershell
[CmdletBinding()] param()
$rel = Get-FsLogixRelease
[pscustomobject]@{
    Version  = $rel.Version        # '3.26.826.17182'
    Url      = $rel.Url
    Checksum = $rel.Checksum       # sha256, lowercase
}
```

Optional keys:

- `Replace` — extra or overriding rewrite rules, `@{ <relative path> = @{ <regex> = <replacement> } }`.
  Only needed for a package that deviates from the default rewrite.
- `InstallScript` — path relative to the package directory; defaults to
  `tools\chocolateyinstall.ps1`.

All three packages rewrite the same two lines (`url = '...'` and
`checksum = '...'`) in `tools\chocolateyinstall.ps1`, so the engine performs that
rewrite **by default** and the currently-triplicated regex map is deleted rather
than ported.

`bis-f` today relies on AU auto-computing `Checksum32` as a side effect of
`update`'s default `-ChecksumFor 32`. Under this contract it calls
`Get-UrlChecksum` explicitly, making the checksum's origin visible in the script.

### Primitives (`lib/ChocoPkg.psm1`)

| Function | Responsibility |
| --- | --- |
| `Get-ChocoPackage` | Discover package directories under a root |
| `Get-NuspecVersion` / `Set-NuspecVersion` | Read/write `<version>` via `XmlDocument` with `PreserveWhitespace = $true` |
| `Test-VersionIsNewer` | `[version]` comparison; throws on unparseable input |
| `Update-PackageFile` | Apply a regex→replacement map to a file, preserving encoding/BOM; throws when a pattern matches nothing |
| `Get-UrlChecksum` | Download to temp, sha256, delete; per-run cache keyed by URL |
| `Invoke-ChocoPack` | `choco pack --outputdirectory <artifacts>`; returns the produced `.nupkg` path |
| `Get-ChocoPushArgs` | Pure function building the `choco push` argument array |
| `Invoke-ChocoPush` | Execute the push; classify the outcome |
| `Invoke-PackageUpdate` | Orchestrate one package through the pipeline |

### Detectors (`lib/Sources.psm1`)

- `Get-GitHubLatestRelease` — `bis-f`, from
  `api.github.com/repos/EUCweb/BIS-F/releases/latest`, selecting the `.msi` asset
  and trimming the `v` prefix from the tag.
- `Get-FsLogixRelease` — `fslogix` and `fslogix-rule`, scraping
  `learn.microsoft.com/en-us/fslogix/overview-release-notes` for external links
  whose text contains a parenthesized version, taking the highest.

Both `fslogix` packages consume the same upstream zip, so the detector fetches
and hashes it once per run (via `Get-UrlChecksum`'s cache) instead of twice. The
cache is a module-scoped variable in `ChocoPkg.psm1`, which works because every
package's `update.ps1` is invoked in the runner's own process — there is no
`Start-Job` fan-out to serialize state across.

The fslogix zip download must keep the flags the current script relies on
(`-SkipCertificateCheck -SkipHeaderValidation -MaximumRetryCount 3
-RetryIntervalSec 5`); the download server requires them.

## Pipeline

Per package, sequentially:

1. `& <pkg>/update.ps1` → detection object.
2. Compare detected version against the nuspec. Not newer and not `-Force` → no
   change; done.
3. Rewrite the install script (`url`, `checksum`); set `<version>` in the nuspec.
4. `choco pack --outputdirectory <artifacts>`; capture the exact `.nupkg` path.
5. `choco push <that path> --source https://push.chocolatey.org --api-key $env:api_key`.

Step 5 carries two specific hardenings against the failure that motivated this
work: the nupkg is pushed **by the path pack returned**, not found by AU's
`Get-ChildItem *.nupkg | Select-Object -First 1`; and the argument array is built
with no conditionally-empty elements, so the PS7 empty-argument behavior cannot
recur. The API key is never written to the log.

### Push outcome classification

| Outcome | Meaning | Commits bump | Affects exit code |
| --- | --- | --- | --- |
| `pushed` | Accepted by the feed | yes | no |
| `already published` | Rejected as a duplicate version | yes | no |
| `failed` | Any other non-zero exit | no | yes |

`already published` exists because versions are sometimes pushed by hand; a
manual push must not make the next nightly run go red.

### Failure handling

Each package runs in its own try/catch. A failure is recorded and the loop
continues to the next package. The runner prints a summary and **exits non-zero
if any package failed**. This is an intentional behavior change from AU, which
reported success while publishing nothing.

Retries are narrow: upstream detection and push get three attempts with a short
backoff. Nothing else is retried.

### Commit

One commit at the end covering every bumped package:

```
Update: fslogix 3.26.826.17182, bis-f 7.1912.6 [skip ci]
```

then push to `master`. This requires `user.name` / `user.email` in the workflow —
commit `fd7747b` removed that step, so it is restored.

The commit **stages only the specific file paths of packages whose outcome was
`pushed` or `already published`** (`git add <nuspec> <install script>` per package),
never `git add -A`. A package that failed at pack or push has already had its files
rewritten on disk by step 3; blanket staging would sweep those modifications into
the commit and record a version bump for a package that was never published. Failed
packages' modifications are left in the working tree uncommitted, which is
inconsequential on an ephemeral runner and visible locally.

## Runner surface

```
update-all.ps1 [-Name <pkg[]>] [-Force] [-CheckOnly] [-NoPush] [-NoCommit] [-Root <path>]
```

`-CheckOnly` detects and reports only, touching nothing. It is named `-CheckOnly`
rather than `-WhatIf` to avoid colliding with PowerShell's built-in `-WhatIf`, and
it matches the workflow's `check` mode. The runner exits `0` when no package
failed (including when packages were skipped or already published) and `1` when
any package failed. `update_vars.ps1` continues
to be dot-sourced when present, for a local API key; a `.gitignore` is added for
it (the repository has none today).

## Workflow changes (`au-update.yml`)

| Trigger | Today | New |
| --- | --- | --- |
| `schedule` / push to `master` | AU with `au_push=true` | `./update-all.ps1` (push + commit) |
| `pull_request` | `test-all.ps1 "random N"` | `./update-all.ps1 -CheckOnly` |
| `workflow_dispatch` | `full` / `test` modes | `mode: full\|check`, optional package list, optional `force` |

The `[AU ...]` / `[PUSH ...]` commit-message parsing is removed; `workflow_dispatch`
inputs cover forcing a package, and that path was a second, separately-broken copy
of the push logic (`Invoke-PushMode` calls AU's `Push-Package` directly and so
carries the same empty-argument bug).

## Testing

Pester, against fixtures — no network, no `choco`, no git:

- `Get-NuspecVersion` / `Set-NuspecVersion` round-trip: the version changes and
  nothing else in the file moves.
- `Update-PackageFile`: rewrites `url`/`checksum` in a fixture install script;
  preserves the UTF-8 BOM those files carry; is idempotent; **throws when a
  pattern matches nothing** (a silent no-match would publish a package pointing at
  the previous URL).
- `Test-VersionIsNewer`: greater / equal / lower / unparseable / `-Force`.
- `Get-ChocoPushArgs`: asserts the argument array contains no empty elements —
  a direct regression test for the bug AU had no way to catch.
- Detectors parse captured fixture HTML (MS Learn) and JSON (GitHub API), so an
  upstream layout change fails a test instead of silently reporting "no updates".

## Migration

1. `lib/` + tests, nothing wired up. Tests pass locally.
2. Port `bis-f`; run `./update-all.ps1 -Name bis-f -CheckOnly`. It is already at the
   latest version, making it the zero-risk canary.
3. Port `fslogix` and `fslogix-rule` onto the shared detector; a `-CheckOnly` run
   shows both detecting `3.26.826.17182`.
4. Swap `au-update.yml`; verify with a `workflow_dispatch` **check** run.
5. Run `./update-all.ps1 -NoPush`. `3.26.826.17182` was already pushed manually,
   so this resyncs the repository (nuspec version, url, checksum for both fslogix
   packages) using the new code, publishing nothing. It exercises every stage
   except the push.
6. Delete `test-all.ps1`, `plugins/`, `update_all.ps1`, `appveyor.yml`. Rewrite the
   README's AU sections, including "Use Windows PowerShell 5.1 for local runs",
   which is no longer true.

Nothing publishes during migration. The push path gets its first real exercise on
the next genuine upstream release.

`fslogix-java` is untouched: retired, not discovered, not modified.

## Risks

- **Detector fragility.** Scraping MS Learn breaks when the page changes. Mitigated
  by fixture tests (which catch parser regressions) and by the runner exiting
  non-zero on failure (which catches "found nothing" at runtime, since the
  detector throws rather than returning empty).
- **Loss of AU's accumulated edge-case handling** (`IgnoreOn` / `RepeatOn` error
  lists). Accepted: narrow retries replace them, and real failures now surface as
  red builds instead of being absorbed.
- **First real push is unverified until upstream ships.** Accepted deliberately in
  exchange for not publishing during migration; push argument construction is
  covered by unit test.
