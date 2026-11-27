# Contributing

## Workflow

1. Open (or pick) an issue.
2. Create a short-lived branch from `main`: `feat/outbox-relay`, `docs/adr-0003`, `ci/trivy-scan`.
3. Open a pull request. CI must be green and the branch up to date with `main`.
4. Squash and merge. The PR title becomes the commit on `main`, so it must follow Conventional Commits
   (checked by the `PR title` workflow).

## Commit / PR titles

[Conventional Commits](https://www.conventionalcommits.org/):

| Type | Use for |
| --- | --- |
| `feat` | new capability |
| `fix` | bug fix |
| `docs` | documentation and ADRs |
| `ci` | workflows |
| `build` | build system, dependencies, Dockerfiles |
| `perf` | performance improvement |
| `refactor`, `test`, `chore`, `revert` | the obvious |

Example: `feat(order-api): publish OrderCreated via outbox`

## Local checks

```bash
cd order-api
./mvnw spotless:apply   # format
./mvnw verify           # what CI runs
```

## Architecture decisions

Any significant decision gets an ADR in [`docs/adr/`](docs/adr/), copied from [`0000-template.md`](docs/adr/0000-template.md),
and a row in the [ADR index](docs/adr/README.md).

## Releases

Versions, tags and the changelog are automated with release-please; see [docs/releasing.md](docs/releasing.md).

## Translations

English is the source of truth. The README is also available in
[Portuguese](README.pt-BR.md) and [Spanish](README.es.md); ADRs and contributor docs stay in English.

Each translation starts with a `translation-of` marker that records the version of the English file
it was translated from. The `Docs` workflow fails when the English file changes and a translation does not:

```bash
scripts/translations.sh check              # what CI runs
scripts/translations.sh sync README.es.md  # after updating a translation, record the new source version
```
