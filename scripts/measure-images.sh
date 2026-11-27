#!/usr/bin/env bash
# Measures the "before" (order-api/Dockerfile.naive) and "after" (order-api/Dockerfile) images
# of step #1 and prints a Markdown report.
#
# Usage: scripts/measure-images.sh [REPORT.md]
#
# Requires: Docker with Buildx, curl, k6, and python3 (or python). Trivy runs as a container.
# Every build runs on a dedicated Buildx builder whose cache is wiped before each cold build,
# so the numbers do not depend on what was built before on this machine. Builds happen on a
# temporary copy of order-api/, so the repository is never modified.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Keep Git Bash on Windows from rewriting container paths such as /var/run/docker.sock.
export MSYS_NO_PATHCONV=1

TRIVY_IMAGE="aquasec/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"
BUILDER="dsl-measure"
BASE_PORT=18080
REPORT="${1:-}"

if python3 -c 'pass' >/dev/null 2>&1; then PY=python3; else PY=python; fi

# On Git Bash, docker, k6 and python are native Windows programs: give them C:/... paths.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

workdir="$(native "$(mktemp -d)")"
cleanup() {
  docker rm -f dsl-measure-naive dsl-measure-optimized >/dev/null 2>&1 || true
  rm -rf "$workdir"
}
trap cleanup EXIT

log() { echo ">> $*" >&2; }
now_ms() { date +%s%3N; }
seconds() { awk -v ms="$1" 'BEGIN { printf "%.1f s", ms / 1000 }'; }

if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
fi
docker buildx inspect --bootstrap "$BUILDER" >/dev/null

declare -A result

measure() {
  local name="$1" dockerfile="$2" port="$3"
  local ctx="$workdir/$name" tag="order-api:measure-$name" container="dsl-measure-$name"

  cp -r order-api "$ctx"
  rm -rf "$ctx/target"

  log "$name: cold build (empty builder cache)"
  docker buildx prune --builder "$BUILDER" --all --force >/dev/null
  local t0
  t0="$(now_ms)"
  docker buildx build --builder "$BUILDER" --load -f "$ctx/$dockerfile" -t "$tag" "$ctx" \
    >"$workdir/$name-cold.log" 2>&1
  result["$name.cold"]="$(seconds $(($(now_ms) - t0)))"

  log "$name: rebuild after a one-line code change"
  echo "// rebuild probe $(date +%s)" >>"$ctx/src/main/java/dev/lab/orderapi/OrderController.java"
  t0="$(now_ms)"
  docker buildx build --builder "$BUILDER" --load -f "$ctx/$dockerfile" -t "$tag" "$ctx" \
    >"$workdir/$name-rebuild.log" 2>&1
  result["$name.rebuild"]="$(seconds $(($(now_ms) - t0)))"

  result["$name.size"]="$(docker image inspect "$tag" --format '{{.Size}}' |
    awk '{ printf "%.0f MB", $1 / 1000 / 1000 }')"
  result["$name.layers"]="$(docker image inspect "$tag" --format '{{len .RootFS.Layers}}')"
  local user
  user="$(docker image inspect "$tag" --format '{{.Config.User}}')"
  result["$name.user"]="${user:-root}"
  if docker run --rm --entrypoint /bin/sh "$tag" -c 'exit 0' >/dev/null 2>&1; then
    result["$name.shell"]="yes"
  else
    result["$name.shell"]="no"
  fi

  log "$name: startup"
  docker rm -f "$container" >/dev/null 2>&1 || true
  t0="$(now_ms)"
  docker run -d --name "$container" -p "$port:8080" "$tag" >/dev/null
  local ready=""
  for _ in $(seq 1 300); do
    if curl -sf "http://localhost:$port/actuator/health/readiness" >/dev/null 2>&1; then
      ready="yes"
      break
    fi
    sleep 0.2
  done
  if [ -z "$ready" ]; then
    docker logs "$container" >&2
    echo "error: $name did not become ready in 60 s" >&2
    exit 1
  fi
  result["$name.ready"]="$(seconds $(($(now_ms) - t0)))"
  result["$name.jvmstart"]="$(docker logs "$container" 2>&1 |
    sed -n 's/.*Started OrderApiApplication in \([0-9.]*\) seconds.*/\1 s/p' | head -n 1)"

  sleep 5
  result["$name.memory"]="$(docker stats --no-stream --format '{{.MemUsage}}' "$container" |
    awk '{ print $1 }')"

  log "$name: load test (k6)"
  k6 run --quiet --summary-export "$workdir/$name-k6.json" \
    -e BASE_URL="http://localhost:$port" k6/load.js >"$workdir/$name-k6.log" 2>&1 || true
  read -r p95 rps failed < <("$PY" - "$workdir/$name-k6.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))["metrics"]
p95 = m["http_req_duration"]["p(95)"]
rps = m["http_reqs"]["rate"]
failed = m["http_req_failed"]["value"] * 100
print(f"{p95:.1f} {rps:.0f} {failed:.2f}")
EOF
)
  result["$name.p95"]="$p95 ms"
  result["$name.rps"]="$rps req/s"
  result["$name.failed"]="$failed %"
  docker rm -f "$container" >/dev/null

  log "$name: vulnerability scan (Trivy)"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v dsl-trivy-cache:/root/.cache \
    "$TRIVY_IMAGE" image --quiet --scanners vuln --format json "$tag" >"$workdir/$name-trivy.json"
  read -r critical high medium low fixable < <("$PY" - "$workdir/$name-trivy.json" <<'EOF'
import json, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
seen, counts, fixable = set(), {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}, 0
for target in report.get("Results") or []:
    for v in target.get("Vulnerabilities") or []:
        key = (v["VulnerabilityID"], v["PkgName"], v.get("InstalledVersion"))
        if key in seen:
            continue
        seen.add(key)
        if v["Severity"] in counts:
            counts[v["Severity"]] += 1
        if v.get("FixedVersion"):
            fixable += 1
print(counts["CRITICAL"], counts["HIGH"], counts["MEDIUM"], counts["LOW"], fixable)
EOF
)
  result["$name.cves"]="$critical / $high / $medium / $low"
  result["$name.fixable"]="$fixable"
}

measure naive Dockerfile.naive "$BASE_PORT"
measure optimized Dockerfile "$((BASE_PORT + 1))"

row() { printf '| %s | %s | %s |\n' "$1" "${result[naive.$2]}" "${result[optimized.$2]}"; }

{
  echo "| Metric | Before (\`Dockerfile.naive\`) | After (\`Dockerfile\`) |"
  echo "| --- | --- | --- |"
  row "Image size" size
  row "Layers" layers
  row "Cold build (empty cache)" cold
  row "Rebuild after a one-line change" rebuild
  row "Time until ready (container start → readiness UP)" ready
  row "Spring Boot startup (as logged)" jvmstart
  row "Memory after startup (idle)" memory
  row "k6 p95 latency (20 VUs, 30 s)" p95
  row "k6 throughput" rps
  row "k6 failed requests" failed
  row "Vulnerabilities: critical / high / medium / low" cves
  row "Vulnerabilities with a fix available" fixable
  row "Shell in the image" shell
  row "Runtime user" user
  echo
  echo "Measured on $(date -u +%Y-%m-%dT%H:%MZ), commit \`$(git rev-parse --short HEAD)\`."
  echo
  echo "- Docker: $(docker version --format '{{.Server.Version}}') on $(docker info --format '{{.OperatingSystem}}, {{.NCPU}} CPUs, {{.MemTotal}}' |
    awk -F', ' '{ printf "%s, %s, %.1f GB RAM", $1, $2, $3 / 1024 / 1024 / 1024 }')"
  echo "- Trivy: \`${TRIVY_IMAGE%@*}\`; k6: $(k6 version | head -n 1 | awk '{ print $2 }')"
} | tee ${REPORT:+"$REPORT"}
