# 0003. Java 25 and Spring Boot 4 for services

- **Status:** Accepted
- **Date:** 2026-11-25
- **Supersedes:** [0002](0002-java-and-spring-boot.md)

## Context

[ADR 0002](0002-java-and-spring-boot.md) chose Java 21 and Spring Boot 3.5. By the time the lab
starts its first step, both are a generation behind:

- Spring Boot 3.5 is the last 3.x line; the current generation is Spring Boot 4 (4.2 at the time
  of writing), built on Spring Framework 7 and Jakarta EE 11.
- Java 25 is the current LTS release.

Step #1 (lean and secure container images) measures image size, startup and vulnerabilities.
Upgrading after that step would invalidate its numbers, so the platform has to be settled first.

## Options considered

1. **Stay on Java 21 + Spring Boot 3.5** — no migration work; starts the series on a line that
   is already out of open-source support, and every later step would have to migrate anyway.
2. **Java 25 + Spring Boot 4.2** — current LTS and current Spring generation; small migration
   now (renamed starters, test slices moved to new packages, Jackson 3).
3. **Java 25 + Spring Boot 3.5** — newer JVM without the framework migration; keeps the
   framework end-of-life problem.

## Decision

Java 25 (LTS) with Spring Boot 4.2, built with Maven 3.10 through the Maven Wrapper.

Java major versions and Spring Boot major/minor versions are upgraded deliberately, through a
new ADR, never by an automatic dependency update.

## Consequences

- The service uses the modular Spring Boot 4 starters (`spring-boot-starter-webmvc`,
  `spring-boot-starter-webmvc-test`), and test slices come from their technology modules
  (e.g. `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest`).
- Container images move to `eclipse-temurin:25` for building and
  `gcr.io/distroless/java25-debian13` for running.
- Java 25 features are available to later steps: virtual threads without pinning on
  `synchronized`, scoped values, and the ahead-of-time cache for faster startup.
- Dependabot must ignore Java major versions in base images and Spring Boot major/minor
  versions, so these upgrades always go through an ADR.
