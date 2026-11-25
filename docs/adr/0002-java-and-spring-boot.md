# 0002. Java 21 and Spring Boot for services

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

The services need a mature ecosystem for messaging (RabbitMQ/Kafka clients), observability
(OpenTelemetry), resilience (Resilience4j) and integration testing (Testcontainers).

## Options considered

1. **Java 21 + Spring Boot** — richest ecosystem for all upcoming concepts; heavier images and slower startup.
2. **Go** — tiny images, fast startup; more hand-rolled plumbing for messaging and sagas.

## Decision

Java 21 (LTS) with Spring Boot 3.5.

## Consequences

- Image size and startup become explicit trade-offs, addressed in step #1 (lean images).
- Virtual threads (Java 21) are available for I/O-heavy workers.
