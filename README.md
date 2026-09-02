# Chocolatey Packages

This repository contains package definitions and update scripts used to maintain and publish selected Chocolatey packages.

## Packages Updated By This Repo

| Package ID | Active | Chocolatey Package | Package Title | What It Provides | Upstream Project |
| --- | --- | --- | --- | --- | -- |
| `bis-f` | ✅ | https://community.chocolatey.org/packages/bis-f | Base Image Script Framework | Image sealing and preparation tooling for Citrix/VMware base images. | https://github.com/EUCweb/BIS-F/ |
| `fslogix` | ✅ | https://community.chocolatey.org/packages/fslogix | FSLogix Apps Agent | FSLogix agent for profile and container-based user profile management. | https://fslogix.com/ |
| `fslogix-java` | ❌ | https://community.chocolatey.org/packages/fslogix-java | FSLogix Version Control Java Rule Editor | FSLogix Java version control rule editor for app-specific Java version targeting. | https://fslogix.com/ |
| `fslogix-rule` | ✅ |  https://community.chocolatey.org/packages/fslogix-rule | FSLogix Apps Rule Editor | FSLogix application masking rule editor. | https://fslogix.com/ |

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

# Bump and pack locally without publishing or committing
./update-all.ps1 -NoPush -NoCommit

# Full run (needs $Env:api_key, or an $Env:api_key = '...' assignment in update_vars.ps1)
./update-all.ps1
```
