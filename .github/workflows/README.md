# Package Update Workflow Notes

## Required GitHub Secrets

Create this in repository settings under `Secrets and variables` -> `Actions`.

- `CHOCOLATEY_API_KEY`: Chocolatey API key used to push packages to
  `https://push.chocolatey.org`. It reaches the runner as the `api_key`
  environment variable.

## Other Environment Variables

- `github_api_key`: set from the run-scoped `${{ github.token }}`. It is used
  only to raise the GitHub API rate limit when detecting the BIS-F release,
  not for git operations.

## Trigger Behavior

- `pull_request` to `master`: runs `update-all.ps1 -CheckOnly`. This only
  detects versions; nothing is written or published.
- `schedule` (daily 04:00 UTC): full run — bump, pack, push, and commit.
- `push` to `master`: full run — bump, pack, push, and commit.
- `workflow_dispatch`: manual run with inputs:
  - `mode`: `check` (detect only, default) or `full` (bump, pack, push, commit).
  - `packages`: optional space-separated package names to limit the run
    (e.g. `fslogix bis-f`).
  - `force`: optional boolean to update even when the detected version is
    not newer.

The Pester suite (`run-tests.ps1`) runs on every trigger before the update
step. A run that fails to publish something it should exits non-zero and
fails the job.

## Artifacts

Workflow uploads (when present):

- `artifacts/*.nupkg`
