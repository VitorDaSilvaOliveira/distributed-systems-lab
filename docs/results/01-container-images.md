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
script on a GitHub-hosted runner (Actions → Measure images → Run workflow); the numbers below come
from that runner, so anyone can reproduce them on the same kind of machine.

## Baseline (2026-11-27, GitHub-hosted runner)

| Metric | Before (`Dockerfile.naive`) | After (`Dockerfile`) |
| --- | --- | --- |
| Image size, compressed (registry / pull) | 294 MB | 95 MB |
| Image size, uncompressed (on disk) | 691 MB | 257 MB |
| Layers | 13 | 39 |
| Cold build (empty cache) | 31.3 s | 47.1 s |
| Rebuild after a one-line change | 29.5 s | 6.2 s |
| Time until ready (container start → readiness UP) | 2.8 s | 2.6 s |
| Spring Boot startup (as logged) | 1.911 s | 1.969 s |
| Memory after startup (idle) | 183.8MiB | 212.5MiB |
| k6 p95 latency (20 VUs, 30 s) | 4.1 ms | 4.1 ms |
| k6 throughput | 194 req/s | 194 req/s |
| k6 failed requests | 0.00 % | 0.00 % |
| Vulnerabilities: critical / high / medium / low | 0 / 4 / 311 / 5 | 0 / 8 / 30 / 25 |
| Vulnerabilities with a fix available | 172 | 0 |
| Shell in the image | yes | no |
| Runtime user | root | 65532 |

[Workflow run](https://github.com/VitorDaSilvaOliveira/distributed-systems-lab/actions/runs/46042855796)
at commit `046ab9f`: Docker 29.4.2 on Ubuntu 26.04.1 LTS, 4 CPUs, 15.6 GB RAM; Trivy 0.76.2, k6 2.4.0.
Timings vary a few seconds between runs (an earlier run measured 26.3 s / 44.3 s cold builds);
compare the two columns, not absolute values.

## What the numbers say

- **Size: −68 % compressed** (294 → 95 MB, what every pull downloads) and **−63 % uncompressed**
  (691 → 257 MB on disk). The runtime image carries a JRE and the application, not Maven, a JDK,
  the sources and the local Maven repository.
- **Rebuild after a one-line change: −79 %** (29.5 → 6.2 s). Dependencies are resolved in their own
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
  Java 25, same application, ~2 s Spring Boot startup and 4.1 ms p95 in both.
- **Memory: +16 %** (184 → 213 MiB idle). The "after" image starts the JVM with
  `-XX:MaxRAMPercentage=75` (instead of the default 25 %), so it sizes a larger heap from the
  container memory. It is a configuration difference, not a cost of distroless, and it becomes a
  deliberate setting once the container gets a memory limit (step #8).
- **Cold build: +50 %** (31.3 → 47.1 s; 2.5× slower on a Windows laptop with Docker Desktop). The
  stages run in parallel and the critical path is the build stage. Profiled locally:

  | Build step (cold, Docker Desktop) | Time |
  | --- | --- |
  | `apt-get install unzip` (needed by the Maven Wrapper checksum check) | 46 s |
  | `./mvnw dependency:go-offline` (all dependencies and plugins) | 39 s |
  | pull of `eclipse-temurin:25-jdk` | 16 s |
  | `./mvnw package` (the actual compilation) | 6 s |
  | pull of the distroless base (in parallel with the build stage) | 61 s |

  The naive build downloads only what `package` needs and installs nothing. The optimized one pays for
  a separate dependency layer (which is what makes rebuilds fast) and for `unzip`. The cold build
  matters on fresh CI runners without a layer cache, so it is the next thing to improve.

## A note on "image size"

`docker images` and `docker image inspect` do not report the same thing on every Docker setup. With
Docker Desktop's containerd image store, the default "disk usage" adds the unpacked layers *and* the
compressed content (985 MB / 352 MB for these images), which is neither what a registry stores nor
what a container uses. The script reports the two sizes that do not depend on the setup: the
compressed size from the OCI manifest and the uncompressed size from the layer history.
