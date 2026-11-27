# Step #1 results: container images

Before/after measurements of the `order-api` image:

- **Before**: [`order-api/Dockerfile.naive`](../../order-api/Dockerfile.naive): one stage on the full
  Maven + JDK image, `COPY . .`, build and run in the same image.
- **After**: [`order-api/Dockerfile`](../../order-api/Dockerfile): multi-stage build, Spring Boot
  layered jar, distroless runtime without a shell, non-root user, base images pinned by digest.

## How to reproduce

```bash
scripts/measure-images.sh report.md
```

The script ([`scripts/measure-images.sh`](../../scripts/measure-images.sh)) builds both images from a
temporary copy of `order-api/` on a dedicated Buildx builder, wipes that builder's cache before each
cold build, starts each container, runs the [k6 load test](../../k6/load.js) against it and scans it
with Trivy. The [`Measure images`](../../.github/workflows/measure-images.yml) workflow runs the same
script on a GitHub-hosted runner (Actions → Measure images → Run workflow).

## Baseline (2026-11-27)

| Metric | Before (`Dockerfile.naive`) | After (`Dockerfile`) |
| --- | --- | --- |
| Image size | 985 MB | 352 MB |
| Layers | 13 | 39 |
| Cold build (empty cache) | 54.5 s | 137.5 s |
| Rebuild after a one-line change | 36.8 s | 14.1 s |
| Time until ready (container start → readiness UP) | 4.6 s | 4.7 s |
| Spring Boot startup (as logged) | 3.329 s | 3.345 s |
| Memory after startup (idle) | 199.9MiB | 227.7MiB |
| k6 p95 latency (20 VUs, 30 s) | 7.9 ms | 9.0 ms |
| k6 throughput | 190 req/s | 189 req/s |
| k6 failed requests | 0.00 % | 0.00 % |
| Vulnerabilities: critical / high / medium / low | 0 / 4 / 311 / 5 | 0 / 8 / 30 / 25 |
| Vulnerabilities with a fix available | 172 | 0 |
| Shell in the image | yes | no |
| Runtime user | root | 65532 |

Measured at commit `8e415a4` on Docker 29.9.3 (Docker Desktop, 8 CPUs, 19.4 GB RAM); Trivy 0.76.2,
k6 2.4.0. Timings depend on the machine and the network; compare the two columns, not absolute values.

## What the numbers say

- **Size: −64 %** (985 → 352 MB). The runtime image carries a JRE and the application, not Maven,
  a JDK, the sources and the local Maven repository.
- **Rebuild after a one-line change: −62 %** (36.8 → 14.1 s). Dependencies are resolved in their own
  layer, so a code change only recompiles the code and replaces the small application layer. The naive
  `COPY . .` invalidates everything and downloads every dependency again.
- **Vulnerabilities: 320 → 63 findings, 172 → 0 with a fix available.** But the "after" image has
  *more* high-severity findings (8 vs. 4), and they mean different things:
  - The 4 in the naive image are in **Maven's own jars** (`plexus-utils`, `commons-beanutils`) from the
    build: build tooling shipped to production with its vulnerabilities. All of them have a fix.
  - The 8 in the distroless image are in two Debian 13 system libraries of the base image
    (`libexpat1`, `libuuid1`), with **no fix released yet**. Rebuilding on a newer digest picks up the
    fix when Debian ships it; that is what the digest pins plus Dependabot are for.
  - Counting findings is not enough: what matters is whether they are fixable, where they live and
    whether the image needs that package at all.
- **Startup and latency: unchanged.** The image changes what ships, not how the JVM runs: same
  Java 25, same application, ~3.3 s Spring Boot startup and ~8–9 ms p95 in both.
- **Memory: +14 %** (200 → 228 MiB idle). The "after" image starts the JVM with
  `-XX:MaxRAMPercentage=75` (instead of the default 25 %), so it sizes a larger heap from the
  container memory. It is a configuration difference, not a cost of distroless, and it becomes a
  deliberate setting once the container gets a memory limit (step #8).
- **Cold build: 2.5× slower** (54.5 → 137.5 s). The stages run in parallel; the critical path is the
  build stage:

  | Build step (cold) | Time |
  | --- | --- |
  | `apt-get install unzip` (needed by the Maven Wrapper checksum check) | 46 s |
  | `./mvnw dependency:go-offline` (all dependencies and plugins) | 39 s |
  | pull of `eclipse-temurin:25-jdk` | 16 s |
  | `./mvnw package` (the actual compilation) | 6 s |
  | pull of the distroless base (in parallel with the build stage) | 61 s |

  The naive build downloads only what `package` needs and installs nothing. The optimized one pays for
  a separate dependency layer (which is what makes rebuilds fast) and for `unzip`. The cold build
  matters on fresh CI runners without a layer cache, so it is the next thing to improve.
