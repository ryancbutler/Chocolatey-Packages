# AU Workflow Notes

## Required GitHub Secrets

Create these in repository settings under `Secrets and variables` -> `Actions`.

- `CHOCOLATEY_API_KEY`: Chocolatey API key used by `Push-Package`.

## Optional Repository Variables

These defaults are currently hardcoded in `.github/workflows/au-update.yml` for parity:

- `github_user_repo`: `ryancbutler/Chocolatey-Packages`
- `au_skip_gist`: `true`

If needed, move them to repository variables later.

## Trigger Behavior

- `push` to `master`: runs full logic and supports commit message routing:
  - `[AU package1 package2]`: forced package updates via `update_all.ps1 -ForcedPackages`.
  - `[PUSH package1 package2]`: direct package `update.ps1` + `choco pack` + `Push-Package`.
- `schedule` (daily 04:00 UTC): runs full `update_all.ps1`.
- `workflow_dispatch`:
  - `mode=full`: runs `update_all.ps1`.
  - `mode=test`: runs `test-all.ps1` random grouping.
- `pull_request` to `master`: test-only mode with publish disabled (`au_push=false`).

## Artifacts

Workflow uploads (when present):

- `update_info.xml`
- `Update-AUPackages.md`
- `Update-Force-Test-*.md`
- `au_temp.zip`

## Notes

- GitHub Actions uses the run-scoped `${{ github.token }}` for AU git operations and releases.
- SMTP email notification env vars are intentionally not set in GitHub Actions.
- Gist publishing is intentionally disabled in GitHub Actions (`au_skip_gist=true`).
- Existing AppVeyor file can remain during migration validation; disable AppVeyor in its UI when ready.
