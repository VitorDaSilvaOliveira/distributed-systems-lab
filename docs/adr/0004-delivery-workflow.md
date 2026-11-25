# 0004. Delivery workflow and repository guardrails

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

Every step of this lab ends in a pull request, a release and a public post, so the path from a
change to a release has to be predictable, reviewable and automated. It also has to hold for the
repository owner: a guardrail with an exception for the person who changes the code the most
protects very little.

While setting the repository up, three problems showed this in practice:

- The branch ruleset required pull requests, but the admin role was on its bypass list, so the
  owner could still push anything straight to `main`. The required status checks list was empty.
- Minutes after the first merge, Dependabot opened 7 pull requests. Two were merged as they
  were; the others changed the Java or Spring Boot generation (one did not even compile), conflicted
  with each other, or rewrote a Windows script with CRLF line endings, a 378-line diff for a
  2-line change.
- Pull requests opened with the workflow's `GITHUB_TOKEN` do not trigger other workflows, so an
  automated release pull request would never get the required checks.

## Options considered

1. **Branching** — GitFlow (long-lived `develop` and release branches) vs. **trunk-based**
   (short-lived branches from `main`). A single deployable line, no release branches to keep in sync.
2. **Merge method** — merge commits, rebase, or **squash**. Squash keeps one commit per pull request
   and a linear history; the pull request title becomes the commit.
3. **Versioning and changelog** — manual tags and notes, semantic-release (publishes on every
   releasable push), or **release-please** (keeps a release pull request open; a human decides when
   to release by merging it).
4. **Token for release automation** — `GITHUB_TOKEN` (does not trigger CI on the pull requests it
   opens), a personal access token (long-lived, tied to a person), or a **GitHub App** (short-lived,
   scoped installation tokens).
5. **Dependency updates** — accept every Dependabot pull request, or **group them, delay new
   releases and reserve platform upgrades for ADRs**.

## Decision

- Trunk-based development on `main`, protected by a ruleset with **no bypass actors**: pull request
  required, squash merge only, linear history, no force pushes or deletion, branch up to date, and
  three required checks: `Build & test`, `Docker image` and `Conventional PR title`.
- Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/); squash
  merge uses the title as the commit on `main`.
- release-please builds the version and changelog from those commits; merging the release pull
  request creates the tag and the GitHub release. Pre-1.0, each step of the series is a minor version.
- Release automation uses a dedicated GitHub App token.
- Workflows run with least-privilege tokens and actions pinned to full commit SHAs.
- Dependabot opens one grouped pull request per ecosystem per week, waits 3 days after a release
  (cooldown), and ignores Java major versions and Spring Boot major/minor versions, which go through
  an ADR ([0003](0003-java-25-and-spring-boot-4.md)).

## Consequences

- Nothing reaches `main` without passing the same checks, including changes by the owner.
- `main` reads as a changelog: one Conventional Commit per pull request.
- More friction: even a typo fix needs a pull request and green checks, and the release pull request
  is usually open between steps, accumulating changes.
- One more piece of infrastructure to maintain: the release GitHub App and its private key
  ([docs/releasing.md](../releasing.md)).
- Dependency noise drops to at most three pull requests a week, each one reviewed.
