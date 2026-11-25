# Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please).

## How it works

1. Every PR is squash-merged, so each commit on `main` is a Conventional Commit (the PR title).
2. On every push to `main`, the `Release` workflow updates a single open **release PR** with the
   next version and the changelog built from those commits.
3. Merging the release PR bumps the version in `.release-please-manifest.json` and
   `order-api/pom.xml`, updates `CHANGELOG.md`, and creates the tag (`vX.Y.Z`) and the GitHub release.

Versioning is pre-1.0: `feat` bumps the minor version (one per step of the series), `fix` the patch.
The release PR can stay open and accumulate changes; merge it when a step is complete.

## One-time setup: release GitHub App

PRs opened with the default `GITHUB_TOKEN` do not trigger workflows, so the release PR would never
get the required CI checks. The workflow uses a short-lived token from a dedicated GitHub App instead.
Until the app is configured, the workflow is skipped.

1. Create a GitHub App (Settings → Developer settings → GitHub Apps → New GitHub App):
   - Name: e.g. `distributed-systems-lab-release`; Homepage URL: the repository URL.
   - Webhook: uncheck **Active**.
   - Repository permissions: **Contents** read and write, **Pull requests** read and write,
     **Issues** read and write (release-please manages labels on the release PR).
   - Where can this app be installed: **Only on this account**.
2. Generate a private key (downloads a `.pem` file) and note the app's **Client ID**.
3. Install the app on this repository only.
4. In the repository (Settings → Secrets and variables → Actions):
   - Variable `RELEASE_APP_CLIENT_ID` = the Client ID.
   - Secret `RELEASE_APP_PRIVATE_KEY` = the full contents of the `.pem` file.
5. Delete the local `.pem` file.
