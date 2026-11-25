# 0001. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

This lab evolves one concept at a time. Without a record, the reasoning behind each choice
(why a queue and not a stream, why outbox and not dual writes) is lost, and the reasoning is
the most valuable part of the project.

## Decision

Every significant decision is recorded as a short ADR in `docs/adr/`, using
[`0000-template.md`](0000-template.md), numbered sequentially, and never edited after
acceptance — a new ADR supersedes an old one.

## Consequences

- Each step of the series has a written rationale that the matching post can link to.
- Small overhead per decision; worth it.
