# Chocolatey Packages

This repository contains Automated Update (AU) scripts and package definitions used to maintain and publish selected Chocolatey packages.

## Packages Updated By This Repo

| Package ID | Active | Chocolatey Package | Package Title | What It Provides | Upstream Project |
| --- | --- | --- | --- | --- | -- |
| `bis-f` | ✅ | https://community.chocolatey.org/packages/bis-f | Base Image Script Framework | Image sealing and preparation tooling for Citrix/VMware base images. | https://github.com/EUCweb/BIS-F/ |
| `fslogix` | ✅ | https://community.chocolatey.org/packages/fslogix | FSLogix Apps Agent | FSLogix agent for profile and container-based user profile management. | https://fslogix.com/ |
| `fslogix-java` | ❌ | https://community.chocolatey.org/packages/fslogix-java | FSLogix Version Control Java Rule Editor | FSLogix Java version control rule editor for app-specific Java version targeting. | https://fslogix.com/ |
| `fslogix-rule` | ✅ |  https://community.chocolatey.org/packages/fslogix-rule | FSLogix Apps Rule Editor | FSLogix application masking rule editor. | https://fslogix.com/ |

## Repository Structure

- `bis-f/`: Chocolatey package files and update script for BIS-F.
- `fslogix/`: Chocolatey package files and update script for FSLogix Apps Agent.
- `fslogix-java/`: Chocolatey package files and update script for FSLogix Java Rule Editor.
- `fslogix-rule/`: Chocolatey package files and update script for FSLogix Rule Editor.
- `update_all.ps1`: Runs AU update checks across packages.
- `test-all.ps1`: Runs AU package test/update validation mode.

## Automation

- AU-based update automation is executed by GitHub Actions in `.github/workflows/au-update.yml`.
- Update reports are generated in files such as `Update-AUPackages.md` and `Update-History.md`.

## Run Updates Locally

Use Windows PowerShell 5.1 for local runs.

```powershell
# From the repository root
git clone https://github.com/majkinetor/au.git $Env:TEMP/au
. "$Env:TEMP/au/scripts/Install-AU.ps1"

# Full update run
./update_all.ps1

# Optional: force selected packages (space-separated)
./update_all.ps1 -ForcedPackages "fslogix bis-f"

# Test mode (random group)
./test-all.ps1 "random 1"
```
