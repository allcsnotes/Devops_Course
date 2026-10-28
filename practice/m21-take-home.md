# Module 21 · Take-Home Tasks: 10 Hands-On DevOps Assignments

Many DevOps and SRE loops include a hands-on round: a live task, or a take-home you do in your own time and then walk through with an engineer ([M21-L01](../interview/m21-l01-how-devops-interviews-work/)). This sheet gives you ten of them, in the shape companies send them: a short brief from the hiring team, starter files, acceptance criteria, how the reviewer scores it, and stretch goals. They get harder as you go, and together they cover the course from a Bash script to a design document.

Each task ends with a **reference solution** in a collapsed block. It was built and run for this sheet, and the output under it is the **real output** of that run (long output trimmed with `…`). Build yours first. A take-home is graded on your README and your reasoning as much as on the code, so compare your trade-offs with the reference too, not just your output.

**How to work:**
- You need Docker Desktop, as set up in Module 01, and nothing else. Every tool runs in a container, pinned to the versions the course verified: `ubuntu:24.04`, `python:3.13.16-slim`, `koalaman/shellcheck:v0.11.0`, `hadolint/hadolint:v2.15.1`, `aquasec/trivy:0.76.0` by digest, `zricethezav/gitleaks:v8.30.1`, `ghcr.io/sigstore/cosign/cosign:v3.1.4`, `hashicorp/terraform:1.16.6`, `prom/prometheus:v3.15.0`, `gitea/gitea:28.1.0` with `gitea/runner:5.1.1`, kind v0.33.0 with `kindest/node:v1.37.0`, kubectl v1.37.1 and Helm 4.3.1.
- Make a folder per task and put the starter files in it. In this repository they're ready in [`m21-take-home/`](m21-take-home/): `tNN/starter/` (plus `t04/lab/`, `t08/troubleshooting-labs/` and `k8s-tools/`), and the reference solutions in `tNN/solution/` (spoilers). Where a task gives you a script, it's the reviewer's: run it, don't edit it.
- **Time boxes** are what a company would expect for a solid submission, not a speed test: tasks 1 to 3 about 1 to 2 hours, tasks 4 to 7 about 2 to 3 hours, tasks 8 to 10 about 3 to 4 hours. If you blow through the box, stop and write down what you'd do next. That's what you'd do in a real take-home.
- Every submission includes a **README**: how to run it, how you tested it, the trade-offs you made, and what you'd do with more time. Reviewers read it first.
- Clean up after each task. The reference runs named everything `m21lab-*`, published host ports only on `127.0.0.1` (21051 to 21055), and removed everything afterwards. Never prune Docker globally, and never delete the shared Docker network called `kind`.
- Results that depend on the date (vulnerability scans, package versions) can differ on your machine. Run dates are given where it matters.
- All passwords, keys and tokens in these tasks are **fake demo values**, made only for these labs.

**What reviewers look for in every task** (the rubrics below add task-specific points):

| Area | What a strong submission shows |
|---|---|
| It works | The acceptance criteria are proven by a test or a command whose output is in the README, not claimed |
| Safe by default | No secrets in files or images, least privilege, pinned versions, nothing published that needn't be |
| Failure handling | What happens when a dependency is down, an input is wrong, or a step fails halfway |
| Clarity | Small, readable files, names that say what they are, comments where a choice isn't obvious |
| Judgement | The README names the trade-offs you made, and what you'd change at real scale |

---

## Task 1 · A robust health-check script, with tests
**Time box: 1 to 2 hours · Difficulty: Easy · Course: [M03-L01 - Bash Basics](../scripts/m03-l01-bash-basics/), [M03-L02 - Robust Scripts](../scripts/m03-l02-robust-scripts/), [M03-B01 - Build a Server Health-Check Toolkit](../scripts/m03-b01-build-a-server-health-check-toolkit/)**

### The brief

> **From the allcsvideos platform team.** Our monitoring agent runs plugins that follow the Nagios convention: exit code 0 for OK, 1 for WARNING, 2 for CRITICAL and 3 for UNKNOWN, with one line of text per check. Write `healthcheck.sh`, a plugin that checks how full one filesystem is and, optionally, whether one URL answers. It will run every minute on every server, so it must never hang, never lie, and never be the reason a page goes out at 3 a.m.

**Interface:**

```text
healthcheck.sh [-d PATH] [-w PCT] [-c PCT] [-u URL] [-t SECONDS] [-j] [-h]
  -d PATH     filesystem to check (default /)
  -w PCT      WARNING when use is at or above PCT (default 80)
  -c PCT      CRITICAL when use is at or above PCT (default 90)
  -u URL      also check that URL answers 2xx or 3xx (anything else, or no answer, is CRITICAL)
  -t SECONDS  connect and total timeout for the URL check (default 5)
  -j          one JSON object per check instead of text
```

**Starter files:** none. An empty folder and a README are the start, as in many real take-homes.

### Acceptance criteria
1. `shellcheck -x` reports nothing on every script (`koalaman/shellcheck:v0.11.0`), exit code 0.
2. The overall exit code is the worst state of all checks.
3. Bad usage (unknown option, missing value, non-numeric or inverted thresholds, stray arguments) exits 3 with a message on stderr, and never runs a check.
4. The URL check can't hang: it uses the timeout, and a refused connection is CRITICAL with the curl exit code in the message.
5. A test suite that runs in `ubuntu:24.04` without network access, and covers every state and every bad-usage case. It exits 0 only when all tests pass.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 30 | Correct states and exit codes, including the worst-state rule |
| 25 | Tests: deterministic (no real disk or network needed), one case per behaviour, readable failures |
| 20 | Robustness: `set -euo pipefail` used knowingly, quoting, timeouts, input validation |
| 15 | Shellcheck clean without blanket disables |
| 10 | README: install, examples, what the exit codes mean |

### Stretch goals
- A third check of your choice (a systemd unit is active, a certificate expires in more than N days) with tests.
- A systemd timer and service that run it every minute, with `SuccessExitStatus=1 2`, as in [M03-B01](../scripts/m03-b01-build-a-server-health-check-toolkit/).
- Performance data after a `|` in the Nagios format, so the agent can graph disk use.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

The script keeps every check in one function that records a state and a message, and the exit code is the worst recorded state. The tests put fake `df` and `curl` commands first on `PATH`, driven by environment variables, so every case is deterministic and needs neither a full disk nor a network.

**`healthcheck.sh`**

```bash
#!/usr/bin/env bash
# healthcheck.sh: check one disk and one HTTP endpoint, Nagios style.
# Exit codes: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN (bad usage or a check that could not run).
set -euo pipefail

readonly VERSION=1.0.0
DISK_PATH=/
WARN=80
CRIT=90
URL=""
TIMEOUT=5
JSON=0
WORST=0
declare -a RESULTS=()

usage() {
  cat <<USAGE
usage: ${0##*/} [-d PATH] [-w PCT] [-c PCT] [-u URL] [-t SECONDS] [-j] [-h] [-V]
  -d PATH     filesystem to check (default /)
  -w PCT      warning when disk use is at or above PCT (default 80)
  -c PCT      critical when disk use is at or above PCT (default 90)
  -u URL      also check that URL answers 2xx or 3xx
  -t SECONDS  connect and total timeout for the URL check (default 5)
  -j          print one JSON object per check instead of text
USAGE
}

die() { echo "UNKNOWN: $*" >&2; exit 3; }

is_int() { [[ $1 =~ ^[0-9]+$ ]]; }

# record NAME STATE(0-3) MESSAGE
record() {
  local name=$1 state=$2 msg=$3 label
  case $state in 0) label=OK ;; 1) label=WARNING ;; 2) label=CRITICAL ;; *) label=UNKNOWN ;; esac
  if (( state > WORST )); then WORST=$state; fi
  if (( JSON )); then
    msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
    RESULTS+=("{\"check\":\"$name\",\"status\":\"$label\",\"message\":\"$msg\"}")
  else
    RESULTS+=("$label $name: $msg")
  fi
}

check_disk() {
  local pct
  if ! pct=$(df -P -- "$DISK_PATH" 2>/dev/null | awk 'NR==2 {sub("%", "", $5); print $5}'); then
    record disk 3 "df failed for $DISK_PATH"; return
  fi
  if ! is_int "${pct:-x}"; then record disk 3 "cannot read usage of $DISK_PATH"; return; fi
  if (( pct >= CRIT )); then record disk 2 "$DISK_PATH is ${pct}% full (critical at ${CRIT}%)"
  elif (( pct >= WARN )); then record disk 1 "$DISK_PATH is ${pct}% full (warning at ${WARN}%)"
  else record disk 0 "$DISK_PATH is ${pct}% full"; fi
}

check_url() {
  local code rc=0
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$TIMEOUT" -m "$TIMEOUT" -- "$URL") || rc=$?
  if (( rc != 0 )); then record http 2 "$URL failed (curl exit $rc)"; return; fi
  case $code in
    2??|3??) record http 0 "$URL answered $code" ;;
    *) record http 2 "$URL answered $code" ;;
  esac
}

main() {
  local opt
  while getopts ':d:w:c:u:t:jhV' opt; do
    case $opt in
      d) DISK_PATH=$OPTARG ;;
      w) WARN=$OPTARG ;;
      c) CRIT=$OPTARG ;;
      u) URL=$OPTARG ;;
      t) TIMEOUT=$OPTARG ;;
      j) JSON=1 ;;
      h) usage; exit 0 ;;
      V) echo "${0##*/} $VERSION"; exit 0 ;;
      :) usage >&2; die "option -$OPTARG needs a value" ;;
      *) usage >&2; die "unknown option -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))
  (( $# == 0 )) || die "unexpected argument: $1"
  if ! is_int "$WARN" || ! is_int "$CRIT"; then die "thresholds must be whole numbers"; fi
  (( WARN < CRIT && CRIT <= 100 )) || die "need warning < critical <= 100 (got $WARN and $CRIT)"
  if ! is_int "$TIMEOUT" || (( TIMEOUT == 0 )); then die "timeout must be a positive whole number"; fi
  command -v df >/dev/null || die "df not found"

  check_disk
  if [[ -n $URL ]]; then
    command -v curl >/dev/null || die "curl not found"
    check_url
  fi
  printf '%s\n' "${RESULTS[@]}"
  exit "$WORST"
}

main "$@"
```

**`tests/run.sh`**

```bash
#!/usr/bin/env bash
# tests/run.sh: tests for healthcheck.sh. Fake df and curl are put first on PATH, so every case is
# deterministic and needs no network. Exits 0 only when every test passes.
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HC=$HERE/../healthcheck.sh
STUBS=$(mktemp -d)
trap 'rm -rf -- "$STUBS"' EXIT

cat > "$STUBS/df" <<'STUB'
#!/usr/bin/env bash
[[ -n ${FAKE_DF_FAIL:-} ]] && exit 1
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/fake 1000 %s 0 %s%% %s\n' "${FAKE_DF_PCT:-10}" "${FAKE_DF_PCT:-10}" "${3:-/}"
STUB
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
if [[ -n ${FAKE_CURL_EXIT:-} ]]; then printf '000'; exit "$FAKE_CURL_EXIT"; fi
printf '%s' "${FAKE_HTTP_CODE:-200}"
STUB
chmod +x "$STUBS/df" "$STUBS/curl"
export PATH="$STUBS:$PATH"

pass=0 fail=0
# expect NAME WANTED_EXIT WANTED_TEXT -- ENV... -- ARGS...
expect() {
  local name=$1 want=$2 text=$3; shift 3
  local -a envs=() args=()
  [[ ${1:-} == -- ]] && shift
  while (( $# )) && [[ $1 != -- ]]; do envs+=("$1"); shift; done
  [[ ${1:-} == -- ]] && shift
  args=("$@")
  local out rc
  out=$(env "${envs[@]}" bash "$HC" "${args[@]}" 2>&1); rc=$?
  if [[ $rc == "$want" && $out == *"$text"* ]]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %s: exit %s (wanted %s), output: %s\n' "$name" "$rc" "$want" "$out"
  fi
}

expect "disk below warning is OK"          0 "OK disk: / is 42% full"          -- FAKE_DF_PCT=42 --
expect "disk at warning is WARNING"        1 "WARNING disk"                    -- FAKE_DF_PCT=80 --
expect "disk at critical is CRITICAL"      2 "CRITICAL disk"                   -- FAKE_DF_PCT=95 --
expect "custom thresholds"                 1 "warning at 50%"                  -- FAKE_DF_PCT=55 -- -w 50 -c 60
expect "df failing is UNKNOWN"             3 "UNKNOWN disk"                    -- FAKE_DF_FAIL=1 --
expect "url 200 is OK"                     0 "OK http: http://x/healthz answered 200" -- FAKE_DF_PCT=1 FAKE_HTTP_CODE=200 -- -u http://x/healthz
expect "url 301 is OK"                     0 "answered 301"                    -- FAKE_DF_PCT=1 FAKE_HTTP_CODE=301 -- -u http://x/
expect "url 503 is CRITICAL"               2 "CRITICAL http: http://x/ answered 503" -- FAKE_DF_PCT=1 FAKE_HTTP_CODE=503 -- -u http://x/
expect "connection refused is CRITICAL"    2 "failed (curl exit 7)"            -- FAKE_DF_PCT=1 FAKE_CURL_EXIT=7 -- -u http://x/
expect "worst state wins"                  2 "WARNING disk"                    -- FAKE_DF_PCT=85 FAKE_HTTP_CODE=500 -- -u http://x/
expect "json output"                       0 '{"check":"disk","status":"OK","message":"/ is 5% full"}' -- FAKE_DF_PCT=5 -- -j
expect "warning must be below critical"    3 "need warning < critical"         -- -- -w 90 -c 80
expect "thresholds must be numbers"        3 "whole numbers"                   -- -- -w ten
expect "unknown option"                    3 "unknown option -x"               -- -- -x
expect "missing option value"              3 "option -u needs a value"         -- -- -u
expect "stray argument"                    3 "unexpected argument: extra"      -- -- extra
expect "help exits 0"                      0 "usage:"                          -- -- -h

printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
```

**Verification.** The first draft failed the shellcheck gate on two `A && B || C` lines (SC2015, explained in question 8 of the final practice sheet). After rewriting them as `if` statements:

```text
$ shellcheck -x healthcheck.sh tests/run.sh; echo "exit $?"
exit 0
```

The tests, in `ubuntu:24.04` (`docker run --rm -v "$PWD":/work:ro -w /work ubuntu:24.04 bash tests/run.sh`):

```text
$ bash tests/run.sh
ok   disk below warning is OK
ok   disk at warning is WARNING
ok   disk at critical is CRITICAL
ok   custom thresholds
ok   df failing is UNKNOWN
ok   url 200 is OK
ok   url 301 is OK
ok   url 503 is CRITICAL
ok   connection refused is CRITICAL
ok   worst state wins
ok   json output
ok   warning must be below critical
ok   thresholds must be numbers
ok   unknown option
ok   missing option value
ok   stray argument
ok   help exits 0
17 passed, 0 failed
exit 0
```

And a real run on an Ubuntu 24.04 server (`--hostname web-01`) with curl installed, an 8 MB in-memory `/data` disk filled to 88%, and an nginx container called `web` on the same network:

```text
$ ./healthcheck.sh -d / -u http://web/
OK disk: / is 10% full
OK http: http://web/ answered 200
exit 0
$ ./healthcheck.sh -d /data -w 70 -c 95
WARNING disk: /data is 88% full (warning at 70%)
exit 1
$ ./healthcheck.sh -d /data -u http://web/missing -j
{"check":"disk","status":"WARNING","message":"/data is 88% full (warning at 80%)"}
{"check":"http","status":"CRITICAL","message":"http://web/missing answered 404"}
exit 2
$ ./healthcheck.sh -d / -u http://web:8080/ -t 2
OK disk: / is 10% full
CRITICAL http: http://web:8080/ failed (curl exit 7)
exit 2
$ ./healthcheck.sh -w 95 -c 90
UNKNOWN: need warning < critical <= 100 (got 95 and 90)
exit 3
```

**Trade-offs worth writing in the README:** `df -P` is used for its stable, one-line-per-filesystem format; any 2xx or 3xx counts as up, because a redirect means the server answered; an unreachable URL is CRITICAL, not UNKNOWN, because for users it is down; and the JSON is built by hand with escaping, to avoid a dependency on `jq` on every server.

</details>

---

## Task 2 · A small, secure image for a Python service
**Time box: 1 to 2 hours · Difficulty: Easy to Medium · Course: [M06-L04 - The Dockerfile, Line by Line](../docker/m06-l04-the-dockerfile-line-by-line/), [M07-L01 - Small, Fast Images](../docker/m07-l01-small-fast-images/), [M07-L03 - Image Security](../docker/m07-l03-image-security/)**

### The brief

> **From the allcsvideos platform team.** `course-search` is a small FastAPI service (keyword search, no AI model). Its Dockerfile works, but it fails our review: it runs as root, ships the tests and the test tools, bakes a password into the image, and takes ten seconds to stop. Replace it with a production Dockerfile. Our reviewer's script, `check.sh`, must pass unchanged.

### Starter files

Save these into one folder, keeping the paths.

**`app/__init__.py`** is an empty file. **`app/main.py`**

```python
"""course-search: a small FastAPI service for the take-home (keyword search, no AI model).

GET /health          {"status": "ok", "version": ..., "courses": N}
GET /search?q=WORDS  the courses whose topics match any word
Config: APP_VERSION (default "dev"), COURSE_INDEX (default data/courses.json)
"""
import json
import os

from fastapi import FastAPI, Response

app = FastAPI(title="course-search")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")


def load_index():
    with open(INDEX, encoding="utf-8") as f:
        return json.load(f)


@app.get("/health")
def health(response: Response):
    try:
        courses = load_index()
    except OSError:
        response.status_code = 503
        return {"status": "degraded", "error": "course index not found"}
    return {"status": "ok", "version": VERSION, "courses": len(courses)}


@app.get("/search")
def search(q: str):
    words = set(q.lower().split())
    hits = [c["title"] for c in load_index() if words & set(c["topics"])]
    return {"query": q, "results": hits}
```

**`data/courses.json`**

```json
[
  {"title": "DSA", "topics": ["arrays", "graphs", "dp", "trees"]},
  {"title": "System Design", "topics": ["caching", "sharding", "queues"]},
  {"title": "Spring Boot", "topics": ["java", "spring", "jpa"]},
  {"title": "GenAI", "topics": ["llm", "rag", "embeddings"]},
  {"title": "DevOps", "topics": ["docker", "kubernetes", "terraform", "linux"]}
]
```

**`tests/test_app.py`**

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_counts_courses():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["courses"] == 5


def test_search_finds_devops():
    r = client.get("/search", params={"q": "Docker basics"})
    assert r.json()["results"] == ["DevOps"]


def test_search_without_match_is_empty():
    assert client.get("/search", params={"q": "cooking"}).json()["results"] == []
```

**`requirements.txt`** and **`requirements-dev.txt`**

```text
fastapi==0.154.0
uvicorn==0.54.0
```

```text
pytest==9.1.1
httpx2==2.15.1
```

**`Dockerfile`** (the one that fails review)

```dockerfile
# The current Dockerfile (works, but fails review)
FROM python:3.13.16-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt -r requirements-dev.txt
ENV DB_PASSWORD=demo-password-123
EXPOSE 8000
CMD uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**`check.sh`** (the reviewer's script; it needs only the docker CLI and publishes one test port on `127.0.0.1:21051`)

```bash
#!/usr/bin/env bash
# check.sh: the reviewer's acceptance checks for task 2. Needs only the docker CLI.
#   bash check.sh [image-tag]     (default m21lab-t02-app:1.0.0)
set -uo pipefail
IMG=${1:-m21lab-t02-app:1.0.0}; C=m21lab-t02-run; MAX_MB=${MAX_MB:-55}
HADOLINT=hadolint/hadolint:v2.15.1
TRIVY=aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
fails=0
ok(){ printf 'PASS %s\n' "$*"; }; bad(){ printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
cleanup(){ docker rm -f "$C" >/dev/null 2>&1 || true; }; trap cleanup EXIT

docker run --rm -i "$HADOLINT" hadolint --no-color - < Dockerfile && ok "hadolint: no findings" || bad "hadolint findings"
docker build -q --target test -t m21lab-t02-app:test . >/dev/null && ok "tests pass in the test stage" || bad "test stage failed"
docker build -q --build-arg APP_VERSION=1.0.0 -t "$IMG" . >/dev/null || { bad "runtime build failed"; exit 1; }

user=$(docker image inspect -f '{{.Config.User}}' "$IMG")
[[ -n $user && ${user%%:*} != 0 && ${user%%:*} != root ]] && ok "runs as user $user" || bad "runs as root"
bytes=$(docker image inspect -f "{{.Size}}" "$IMG"); mb=$(( bytes / 1000 / 1000 ))
(( mb <= MAX_MB )) && ok "image content size ${mb} MB (limit ${MAX_MB} MB)" || bad "image size ${mb} MB > ${MAX_MB} MB"
docker image inspect -f '{{json .Config.Env}}' "$IMG" | grep -qi 'password\|secret\|token' \
  && bad "a secret-looking variable is baked into the image" || ok "no secret-looking variables in the image config"
docker run --rm --entrypoint python "$IMG" -c 'import pytest' >/dev/null 2>&1 \
  && bad "pytest is in the runtime image" || ok "no test tools in the runtime image"
docker run --rm --entrypoint python "$IMG" -m pip --version >/dev/null 2>&1 \
  && bad "pip is in the runtime image" || ok "no pip in the runtime image"

docker run -d --name "$C" --read-only --cap-drop ALL --security-opt no-new-privileges \
  -p 127.0.0.1:21051:8000 "$IMG" >/dev/null
for _ in $(seq 30); do [[ $(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$C") == healthy ]] && break; sleep 1; done
[[ $(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$C") == healthy ]] \
  && ok "healthy with --read-only, --cap-drop ALL, no-new-privileges" || bad "not healthy: $(docker logs --tail 3 "$C" 2>&1)"
body=$(docker run --rm --network container:"$C" curlimages/curl:8.17.0 -s 'http://127.0.0.1:8000/search?q=docker' 2>/dev/null || true)
[[ $body == *DevOps* ]] && ok "GET /search?q=docker -> $body" || bad "search answered: $body"
start=$(date +%s); docker stop -t 10 "$C" >/dev/null; secs=$(( $(date +%s) - start ))
code=$(docker inspect -f '{{.State.ExitCode}}' "$C")
(( secs < 5 )) && ok "stopped on SIGTERM in ${secs} s (exit code $code)" || bad "stop took ${secs} s (exit code $code): SIGTERM not handled"

if docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v m21lab-t02-trivy:/root/.cache "$TRIVY" image \
     --quiet --table-mode detailed --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMG"; then
  ok "trivy: no fixable HIGH or CRITICAL vulnerabilities"
else bad "trivy found fixable HIGH or CRITICAL vulnerabilities"; fi
printf '%d check(s) failed\n' "$fails"; (( fails == 0 ))
```

### Acceptance criteria
1. `bash check.sh` prints `0 check(s) failed`: hadolint clean; the unit tests run in a `test` build stage; the runtime image runs as a non-root numeric user; its content size is at most 55 MB; no secret-looking variables, no pytest and no pip in the runtime image; healthy with `--read-only --cap-drop ALL --security-opt no-new-privileges`; stops on SIGTERM in under 5 seconds; and Trivy finds no fixable HIGH or CRITICAL vulnerabilities.
2. The same Dockerfile builds the image for any version with `--build-arg APP_VERSION=...`, and `/health` reports it.
3. A `.dockerignore`, so the build context holds only what the build needs.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 30 | `check.sh` passes; the reviewer also reads why each check passes |
| 20 | Stage design: dependencies cached before the source, tests in their own stage, nothing extra in runtime |
| 20 | Security: non-root, no shell-form CMD, no secrets, a health check, read-only friendly |
| 15 | Size and scan results explained, including what you removed and why it was flagged |
| 15 | README: build and run commands, the numbers before and after |

### Stretch goals
- A distroless runtime stage, and a comparison of size, scan results and how you'd debug it (`docker debug`).
- A multi-platform build (`linux/amd64,linux/arm64`) and an SBOM with Syft.
- Pin the base image by digest, and say how you'd keep that pin up to date.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1
# course-search: build, test and runtime stages. Only the runtime stage ships.
ARG PYTHON_IMAGE=python:3.13.16-slim

# 1) build: a virtual environment with the runtime dependencies only
FROM ${PYTHON_IMAGE} AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /src
COPY requirements.txt .
RUN pip install -r requirements.txt \
 && pip uninstall -y pip

# 2) test: the build venv + test tools + the tests. `docker build --target test .` fails if a test fails.
FROM build AS test
COPY requirements-dev.txt .
RUN python -m ensurepip && python -m pip install -r requirements-dev.txt
WORKDIR /app
COPY app/ app/
COPY data/ data/
COPY tests/ tests/
RUN python -m pytest -q

# 3) runtime: slim Python, the venv and the app; no pip, no tests, no secrets, not root
FROM ${PYTHON_IMAGE} AS runtime
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    PATH=/opt/venv/bin:$PATH \
    COURSE_INDEX=/app/data/courses.json
# pip is not needed at run time, and its vendored libraries are what scanners flag
RUN python -m pip uninstall -y pip \
 && groupadd --gid 10001 app \
 && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build /opt/venv /opt/venv
COPY app/ app/
COPY data/ data/
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**`.dockerignore`**

```text
.git
**/__pycache__
**/*.pyc
.pytest_cache
.venv
.env
*.md
Dockerfile*
check.sh
```

**Before.** `check.sh` on the starter image (22 October 2026):

```text
-:5 DL3042 warning: Avoid use of cache directory with pip. Use `pip install --no-cache-dir <package>`
-:6 DL3064 warning: Potentially sensitive data should not be used in the `ARG` or `ENV` commands
-:8 DL3025 warning: Use arguments JSON notation for CMD and ENTRYPOINT arguments
FAIL hadolint findings
ERROR: failed to build: failed to solve: target stage "test" could not be found

View build details: docker-desktop://dashboard/build/desktop-linux/desktop-linux/j518uuqgt5g02go6rvj9ftltg
FAIL test stage failed
FAIL runs as root
FAIL image size 64 MB > 55 MB
FAIL a secret-looking variable is baked into the image
FAIL pytest is in the runtime image
FAIL pip is in the runtime image
FAIL not healthy: INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
PASS GET /search?q=docker -> {"query":"docker","results":["DevOps"]}
FAIL stop took 10 s (exit code 137): SIGTERM not handled

Python (python-pkg)
===================
…
```

The 10-second stop with exit code 137 is the shell-form CMD: `/bin/sh -c` is PID 1 and never passes SIGTERM to uvicorn, so Docker waits and then kills it. The five Trivy findings are all libraries vendored inside **pip**, which the service never uses at run time.

**After.** The first draft still failed one check: hadolint DL3045, "`COPY` to a relative destination without `WORKDIR` set", in the build stage. With `WORKDIR /src` added:

```text
PASS hadolint: no findings
PASS tests pass in the test stage
PASS runs as user 10001:10001
PASS image content size 48 MB (limit 55 MB)
PASS no secret-looking variables in the image config
PASS no test tools in the runtime image
PASS no pip in the runtime image
PASS healthy with --read-only, --cap-drop ALL, no-new-privileges
PASS GET /search?q=docker -> {"query":"docker","results":["DevOps"]}
PASS stopped on SIGTERM in 1 s (exit code 0)
PASS trivy: no fixable HIGH or CRITICAL vulnerabilities
0 check(s) failed
```

`docker images` showed the runtime image at 48.7 MB content size (225 MB on disk), against 64.5 MB (277 MB on disk) for the starter.

**Trade-offs worth writing in the README:** pip is removed from both the venv and the base Python, which clears the scan findings and stops anyone from installing packages into a running container; the health check uses Python's own `urllib`, so no curl is needed in the image; and the test stage reuses the build stage's venv, so the tests run against exactly the dependency versions that ship.

</details>

---

## Task 3 · A Compose stack with health checks and a reverse proxy
**Time box: 2 hours · Difficulty: Medium · Course: [M06-L06 - Container Networking](../docker/m06-l06-container-networking/), [M07-L02 - Docker Compose](../docker/m07-l02-docker-compose/), [M07-B01 - Containerise the allcsvideos Stack](../docker/m07-b01-containerise-the-allcsvideos-stack/)**

### The brief

> **From the allcsvideos platform team.** The course-list API reads from PostgreSQL and caches in Redis. Its `compose.yaml` "works on my machine": every port is published, the database password is in the file, nothing waits for anything, and a crash takes the API down for good. Make it production-shaped for a single host: nginx in front as the only published service, health checks everywhere, startup in the right order, secrets out of the environment, and data that survives a restart.

### Starter files

**`api/app.py`**

```python
"""api: the allcsvideos course-list API for the Compose take-home (stdlib HTTP server + PostgreSQL + Redis).

GET /api/courses  courses from PostgreSQL, cached in Redis for 30 s (header X-Cache: HIT or MISS)
GET /healthz      200 only when PostgreSQL and Redis both answer, else 503
Settings: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD_FILE (a file holding the password), REDIS_HOST, PORT (8080)
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg
import redis

with open(os.environ["DB_PASSWORD_FILE"], encoding="utf-8") as f:
    DB_PASSWORD = f.read().strip()
DSN = f"host={os.environ['DB_HOST']} dbname={os.environ['DB_NAME']} user={os.environ['DB_USER']} password={DB_PASSWORD} connect_timeout=2"
CACHE = redis.Redis(host=os.environ.get("REDIS_HOST", "redis"), socket_timeout=2)


def courses():
    cached = CACHE.get("courses")
    if cached:
        return json.loads(cached), "HIT"
    with psycopg.connect(DSN) as conn:
        rows = conn.execute("SELECT id, title FROM courses ORDER BY id").fetchall()
    data = [{"id": r[0], "title": r[1]} for r in rows]
    CACHE.setex("courses", 30, json.dumps(data))
    return data, "MISS"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path == "/healthz":
                with psycopg.connect(DSN) as conn:
                    conn.execute("SELECT 1")
                CACHE.ping()
                return self.reply(200, {"status": "ok"})
            if self.path == "/api/courses":
                data, hit = courses()
                return self.reply(200, data, {"X-Cache": hit})
            return self.reply(404, {"error": "not found"})
        except (psycopg.Error, redis.RedisError) as e:
            return self.reply(503, {"error": type(e).__name__})

    def reply(self, status, body, headers=None):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
```

**`api/requirements.txt`**

```text
psycopg[binary]==3.3.6
redis==8.1.0
```

**`api/Dockerfile`**

```dockerfile
FROM python:3.13.16-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && python -m pip uninstall -y pip \
 && useradd --uid 10001 --no-create-home app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "app.py"]
```

**`db/init.sql`**

```sql
CREATE TABLE courses (id text PRIMARY KEY, title text NOT NULL);
INSERT INTO courses VALUES
  ('devops', 'DevOps: From Linux to Kubernetes in Production'),
  ('dsa', 'Data Structures and Algorithms'),
  ('genai', 'Generative AI with Python');
```

**`compose.yaml`** (the one to replace)

```yaml
# The current compose file: it "works on my machine". Make it production-shaped (see the brief).
services:
  api:
    build: ./api
    ports: ["8080:8080"]
    environment:
      DB_HOST: db
      DB_NAME: allcs
      DB_USER: postgres
      DB_PASSWORD_FILE: /run/pw
      REDIS_HOST: redis
    volumes: ["./pw.txt:/run/pw"]
  db:
    image: postgres:latest
    ports: ["5432:5432"]
    environment:
      POSTGRES_PASSWORD: demo-password-123
      POSTGRES_DB: allcs
    volumes: ["./db/init.sql:/docker-entrypoint-initdb.d/init.sql"]
  redis:
    image: redis
    ports: ["6379:6379"]
```

**`pw.txt`** holds one line, `demo-password-123` (a fake value).

### Acceptance criteria
1. `docker compose up -d --wait` exits 0 with every service healthy, from an empty Docker host.
2. Only the reverse proxy publishes a port, and only on `127.0.0.1`.
3. `GET /api/courses` through the proxy returns the courses; a second call within 30 s is a cache hit (`X-Cache: HIT`).
4. The database is not reachable from the network the proxy is on.
5. No password in any container's environment or in `compose.yaml`.
6. If the API process crashes, it's restarted and serves again without anyone touching it.
7. Data survives `docker compose down` and `up`.
8. Every image pinned to a version (no `latest`).

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 25 | Health checks that test the real thing, and `depends_on` conditions that use them |
| 25 | Network design: frontend and backend networks, internal backend, one published port |
| 20 | Secrets handled as files, not environment variables; least privilege (read-only, dropped capabilities, non-root) |
| 15 | Resilience: restart policy proven with a real crash, limits on memory and CPU, log rotation |
| 15 | A check script or a README section that proves each criterion |

### Stretch goals
- A request ID created by nginx, passed to the API and logged by both.
- A `backup` profile with a one-shot service that writes a `pg_dump` into a volume, and a restore you've tested.
- `docker compose watch` for development, without changing the production file.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`compose.yaml`**

```yaml
# allcsvideos course API: nginx -> api -> PostgreSQL + Redis. Only nginx is published, on 127.0.0.1.
name: m21lab-t03

x-common: &common
  restart: unless-stopped
  labels: {course: devops}
  security_opt: ["no-new-privileges:true"]
  logging:
    driver: json-file
    options: {max-size: "10m", max-file: "3"}

services:
  proxy:
    <<: *common
    image: nginxinc/nginx-unprivileged:1.29.8-alpine
    ports: ["127.0.0.1:21053:8080"]
    volumes: ["./proxy/default.conf:/etc/nginx/conf.d/default.conf:ro"]
    networks: [frontend]
    read_only: true
    tmpfs: [/tmp]
    mem_limit: 64m
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/nginx-health"]
      interval: 5s
      timeout: 2s
      retries: 3
    depends_on:
      api: {condition: service_healthy}

  api:
    <<: *common
    build: ./api
    image: m21lab-t03-api:1.0.0
    init: true
    environment:
      DB_HOST: db
      DB_NAME: allcs
      DB_USER: allcs
      DB_PASSWORD_FILE: /run/secrets/db_password
      REDIS_HOST: redis
    secrets: [db_password]
    networks: [frontend, backend]
    read_only: true
    cap_drop: [ALL]
    mem_limit: 128m
    cpus: 0.5
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"]
      interval: 5s
      timeout: 3s
      retries: 3
      start_period: 10s
    depends_on:
      db: {condition: service_healthy}
      redis: {condition: service_healthy}

  db:
    <<: *common
    image: postgres:18.6-alpine3.24
    environment:
      POSTGRES_USER: allcs
      POSTGRES_DB: allcs
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]
    volumes:
      - db-data:/var/lib/postgresql
      - ./db/init.sql:/docker-entrypoint-initdb.d/10-init.sql:ro
    networks: [backend]
    mem_limit: 256m
    healthcheck:
      test: ["CMD", "pg_isready", "-h", "localhost", "-U", "allcs", "-d", "allcs"]
      interval: 5s
      timeout: 3s
      retries: 10

  redis:
    <<: *common
    image: redis:8.10.2-alpine3.23
    command: ["redis-server", "--save", "", "--appendonly", "no", "--maxmemory", "32mb", "--maxmemory-policy", "allkeys-lru"]
    networks: [backend]
    read_only: true
    mem_limit: 64m
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 2s
      retries: 3

networks:
  frontend: {}
  backend: {internal: true}

volumes:
  db-data: {}

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

**`proxy/default.conf`**

```nginx
# nginx in front of the API: the only published service
upstream api {
  zone api 64k;
  server api:8080 max_fails=1 fail_timeout=5s;
}
server {
  listen 8080;
  server_tokens off;
  location = /nginx-health { access_log off; return 200 "ok\n"; }
  location /api/ {
    proxy_pass http://api;
    proxy_set_header Host $host;
    proxy_set_header X-Request-ID $request_id;
    add_header X-Request-ID $request_id always;
    proxy_connect_timeout 2s;
    proxy_read_timeout 5s;
  }
  location / { return 404 "not found\n"; }
}
```

**`secrets/db_password.txt`** holds one line, `demo-password-123-FAKE`. The API, `init.sql` and the API's Dockerfile are unchanged from the starter.

**`check.sh`** (the proof for the README; it curls from a throwaway container in the proxy's network namespace, so nothing is installed on the laptop)

```bash
#!/usr/bin/env bash
# check.sh: the reviewer's acceptance checks for task 3. Needs only the docker CLI. Run it next to compose.yaml.
set -uo pipefail
P=m21lab-t03; URL=http://127.0.0.1:8080; fails=0
ok(){ printf 'PASS %s\n' "$*"; }; bad(){ printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }
# curl from a throwaway container on the host side of the published port (nothing installed on the laptop)
hcurl(){ docker run --rm --network container:${P}-proxy-1 curlimages/curl:8.17.0 "$@"; }

start=$(date +%s)
docker compose up -d --build --wait --wait-timeout 120 >/dev/null 2>&1 && ok "compose up --wait: all services healthy in $(( $(date +%s) - start )) s" || bad "compose up --wait failed"
docker compose ps --format '{{.Service}} {{.Status}}' | sort
pub=$(docker compose ps --format "{{.Ports}}" | grep -c -- "->" || true)
[[ $pub == 1 ]] && ok "exactly one service publishes a port" || bad "$pub services publish ports"
docker compose port proxy 8080 | grep -q '^127.0.0.1:' && ok "proxy is published on 127.0.0.1 only: $(docker compose port proxy 8080)" || bad "proxy is not bound to 127.0.0.1"

h1=$(hcurl -s -D - -o /dev/null $URL/api/courses | tr -d '\r' | grep -i '^x-cache' ); h2=$(hcurl -s -D - -o /dev/null $URL/api/courses | tr -d '\r' | grep -i '^x-cache')
[[ $h1 == *MISS* && $h2 == *HIT* ]] && ok "first request $h1, second $h2" || bad "cache headers: [$h1] [$h2]"
body=$(hcurl -s $URL/api/courses); [[ $body == *devops* ]] && ok "GET /api/courses through nginx returns the courses" || bad "body: $body"

docker run --rm --network ${P}_frontend postgres:18.6-alpine3.24 pg_isready -h db -t 3 >/dev/null 2>&1 \
  && bad "the database is reachable from the frontend network" || ok "the database is not reachable from the frontend network"
docker inspect ${P}-db-1 ${P}-api-1 --format '{{json .Config.Env}}' | grep -q 'demo-password' \
  && bad "the password is in a container's environment" || ok "no password in any container environment (secrets file instead)"

# a real crash: kill the API process (not "docker stop", which restart policies treat as manual)
docker compose exec -T api sh -c 'kill -KILL $(cat /proc/1/task/1/children)' >/dev/null 2>&1
code=$(hcurl -s -o /dev/null -w '%{http_code}' $URL/api/courses)
echo "     right after the crash, nginx answers $code"
for _ in $(seq 40); do [[ $(docker inspect -f '{{.State.Health.Status}}' ${P}-api-1) == healthy ]] && break; sleep 1; done
rc=$(docker inspect -f '{{.RestartCount}}' ${P}-api-1); code=$(hcurl -s -o /dev/null -w '%{http_code}' $URL/api/courses)
[[ $rc -ge 1 && $code == 200 ]] && ok "api crashed, was restarted (RestartCount=$rc) and serves again: HTTP $code" || bad "after crash: RestartCount=$rc HTTP $code"

docker compose exec -T db psql -U allcs -d allcs -qc "INSERT INTO courses VALUES ('k8s', 'Kubernetes in Production')" >/dev/null
docker compose down >/dev/null 2>&1; docker compose up -d --wait --wait-timeout 120 >/dev/null 2>&1
n=$(docker compose exec -T db psql -U allcs -d allcs -tAc "SELECT count(*) FROM courses")
[[ $n == 4 ]] && ok "data survives compose down and up (4 courses)" || bad "after down/up: $n courses"
printf '%d check(s) failed\n' "$fails"; (( fails == 0 ))
```

**Verification**, from an empty host (`docker compose down -v` first):

```text
$ bash check.sh
PASS compose up --wait: all services healthy in 20 s
api Up 11 seconds (healthy)
db Up 17 seconds (healthy)
proxy Up 5 seconds (healthy)
redis Up 17 seconds (healthy)
PASS exactly one service publishes a port
PASS proxy is published on 127.0.0.1 only: 127.0.0.1:21053
PASS first request X-Cache: MISS, second X-Cache: HIT
PASS GET /api/courses through nginx returns the courses
PASS the database is not reachable from the frontend network
PASS no password in any container environment (secrets file instead)
     right after the crash, nginx answers 200
PASS api crashed, was restarted (RestartCount=1) and serves again: HTTP 200
PASS data survives compose down and up (4 courses)
0 check(s) failed
exit 0
```

The crash was real: `kill -KILL` on the API process inside the container (with `init: true`, tini is PID 1 and the app is its child), not `docker stop`, which restart policies treat as a manual stop. Docker restarted it before the next request arrived, so nginx answered 200 straight away; a slower-starting app would have shown a 502 for a moment, which is why the proxy has `max_fails` and short timeouts.

**Trade-offs worth writing in the README:** Compose secrets on a single host are bind-mounted files, which keeps them out of `docker inspect` and the environment, but they aren't encrypted at rest; Redis runs as a pure cache (no persistence), so losing it costs only cache misses; the backend network is `internal`, so the database and Redis can't reach the internet either; and with one host, Compose is the right tool, while a second host is the point to move to Kubernetes or ECS.

</details>

---

## Task 4 · A CI pipeline with lint, test, scan and build gates
**Time box: 2 to 3 hours · Difficulty: Medium · Course: [M08-L02 - GitHub Actions Anatomy](../ci/m08-l02-github-actions-anatomy/), [M08-L03 - Build, Test and Lint](../ci/m08-l03-build-test-and-lint/), [M08-L04 - Building and Pushing Images](../ci/m08-l04-building-and-pushing-images/), [M18-L01 - Shift Left](../security/m18-l01-shift-left/)**

### The brief

> **From the allcsvideos platform team.** We're moving `course-search` (from task 2) to GitHub Actions. Write `.github/workflows/ci.yml` so that every pull request and every push to main runs four gates: lint (the Dockerfile and the shell scripts), unit tests, security scans (secrets in the whole git history, and vulnerable dependencies), and a build of the runtime image that is smoke-tested and scanned. Build only runs when the other three pass. We'll run your workflow unchanged in our local CI lab before we look at anything else.

### Starter files

The repository is task 2's reference solution (`app/`, `data/`, `tests/`, `requirements*.txt`, `Dockerfile`, `.dockerignore` without the `check.sh` line), plus this smoke test:

**`scripts/smoke.sh`**

```bash
#!/usr/bin/env bash
# smoke.sh IMAGE: start the image the way production does, wait for its health check, call one endpoint.
set -euo pipefail
image=${1:?usage: smoke.sh IMAGE}
name=smoke-$$
host=${SMOKE_HOST:-127.0.0.1}
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" --read-only --cap-drop ALL --security-opt no-new-privileges -p 18000:8000 "$image" >/dev/null
for _ in $(seq 30); do
  status=$(docker inspect -f '{{.State.Health.Status}}' "$name")
  [[ $status == healthy ]] && break
  sleep 1
done
echo "health: $status"
[[ $status == healthy ]]
curl -fsS --max-time 5 "http://$host:18000/search?q=docker"
echo
```

**The local CI lab.** Gitea Actions runs the same workflow syntax as GitHub Actions, so a Gitea server and its runner on your laptop run your file unchanged (on GitHub the file and the UI look the same apart from names). Jobs get their own Docker daemon (`docker:29.5.3-dind`, TLS), never your laptop's Docker socket. Save these two files as `lab/lab.sh` and `lab/runner/config.yaml`:

```zsh
#!/bin/zsh
# lab.sh up | push DIR MESSAGE | wait | logs JOB | down : a local CI lab for take-home task 4.
#  Gitea 28.1.0 (Gitea Actions runs GitHub Actions workflow syntax), the Gitea runner 5.1.1, and a separate
#  docker:29.5.3-dind daemon (TLS) for the jobs. Everything is named m21lab-t04-*. Lab-only FAKE password.
set -euo pipefail
H=${0:A:h}; SRC=${2:+${2:A}}   # resolve paths before cd
cd $H
V=m21lab-t04; N=$V-net; G=$V-gitea; D=$V-docker; R=$V-runner; L=(--label course=devops)
REPO=asha/course-search
api(){ docker run --rm --network $N curlimages/curl:8.17.0 -s -H "Authorization: token $(cat .token)" "http://gitea:3000/api/v1$1"; }
case ${1:-} in
up)
  docker network create $L $N >/dev/null
  for v in gitea-data dind-certs dind-data runner-data git; do docker volume create $L $V-$v >/dev/null; done
  docker run -d $L --name $G --hostname gitea --network $N --network-alias gitea -p 127.0.0.1:21054:3000 \
    --memory 384m -v $V-gitea-data:/data -e USER_UID=1000 -e USER_GID=1000 -e GITEA__database__DB_TYPE=sqlite3 \
    -e GITEA__security__INSTALL_LOCK=true -e GITEA__server__ROOT_URL=http://gitea:3000/ -e GITEA__server__DOMAIN=gitea \
    -e GITEA__server__DISABLE_SSH=true -e GITEA__service__DISABLE_REGISTRATION=true -e GITEA__actions__ENABLED=true \
    -e GITEA__repository__DEFAULT_BRANCH=main gitea/gitea:28.1.0 >/dev/null
  docker run -d $L --name $D --hostname docker --network $N --network-alias docker --privileged --memory 1536m \
    -e DOCKER_TLS_CERTDIR=/certs -v $V-dind-certs:/certs -v $V-dind-data:/var/lib/docker docker:29.5.3-dind >/dev/null
  until docker exec $G curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; do sleep 1; done
  docker exec -u git $G gitea admin user create --username asha --email asha@example.com \
    --password fake-lab-pass-asha --admin --must-change-password=false >/dev/null
  docker exec -u git $G gitea admin user generate-access-token --username asha --token-name lab --scopes all --raw > .token
  chmod 600 .token
  docker run --rm --network $N curlimages/curl:8.17.0 -s -o /dev/null -w 'create repo: HTTP %{http_code}\n' \
    -H "Authorization: token $(cat .token)" -H 'Content-Type: application/json' \
    -d '{"name":"course-search","default_branch":"main","auto_init":false}' http://gitea:3000/api/v1/user/repos
  tok=$(docker exec -u git $G gitea actions generate-runner-token | tail -1)
  docker run -d $L --name $R --hostname runner-01 --network $N --memory 256m \
    -v /var/run/docker.sock:/var/run/docker.sock -v $V-runner-data:/data -v $H/runner/config.yaml:/config.yaml:ro \
    -e CONFIG_FILE=/config.yaml -e GITEA_INSTANCE_URL=http://gitea:3000/ -e GITEA_RUNNER_REGISTRATION_TOKEN=$tok \
    -e GITEA_RUNNER_NAME=runner-01 gitea/runner:5.1.1 >/dev/null
  unset tok
  for i in {1..60}; do docker logs $R 2>&1 | grep -q 'declare successfully\|declared successfully' && break; sleep 1; done
  docker logs $R 2>&1 | grep -i 'declare' | tail -1
  echo lab up ;;
push)   # push DIR MESSAGE: replace the repo's files with DIR and push one commit
  docker run --rm --network $N -v "$SRC":/src:ro -v $V-git:/git -v $H/.token:/run/t:ro -w /git --entrypoint sh alpine/git:v2.49.1 -c '
    [ -d .git ] || { git init -q -b main . && git config user.name Asha && git config user.email asha@example.com; }
    find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    cp -R /src/. . && git add -A && git commit -qm "$1" && git log --oneline -1
    git push -q "http://asha:$(cat /run/t)@gitea:3000/'$REPO'.git" main 2>&1 | grep -v "^remote:" || true' sh "$3" ;;
wait)   # wait for the newest run to finish, then print its jobs
  for i in {1..180}; do
    s=$(api "/repos/$REPO/actions/runs?limit=1" | docker run --rm -i ghcr.io/jqlang/jq:1.8.1 -r '.workflow_runs[0] | "\(.id) \(.status) \(.conclusion)"')
    [[ $s == *completed* ]] && break; sleep 5; done
  id=${s%% *}; echo "run $s"
  api "/repos/$REPO/actions/runs/$id/jobs" | docker run --rm -i ghcr.io/jqlang/jq:1.8.1 -r '.jobs[] | "\(.id)\t\(.name)\t\(.conclusion)\t\(.started_at[11:19])-\(.completed_at[11:19])"' ;;
logs)   api "/repos/$REPO/actions/jobs/$2/logs" ;;
down)
  docker rm -f $R >/dev/null 2>&1 || true
  for c in $(docker ps -aq --filter name=GITEA-ACTIONS-TASK --filter network=$N); do docker rm -f -v $c >/dev/null; done
  docker rm -f $D $G >/dev/null 2>&1 || true
  for v in gitea-data dind-certs dind-data runner-data git; do docker volume rm $V-$v >/dev/null 2>&1 || true; done
  docker network rm $N >/dev/null 2>&1 || true; rm -f .token; echo lab down ;;
*) sed -n 2,4p $0; exit 1 ;;
esac
```

```yaml
# Gitea runner (gitea/runner:5.1.1) for the task 4 lab. Jobs get their own Docker daemon (m21lab-t04-docker),
# never the laptop's Docker socket.
log:
  level: info
runner:
  file: /data/.runner
  capacity: 2
  envs:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_VERIFY: "1"
    DOCKER_CERT_PATH: /certs/client
  labels:
    - "ubuntu-latest:docker://gitea/runner-images:ubuntu-24.04-v26.10.01"
cache:
  enabled: false
container:
  network: m21lab-t04-net
  options: --label course=devops --volume m21lab-t04-dind-certs:/certs:ro
  valid_volumes:
    - m21lab-t04-dind-certs:ro
  docker_host: "-"
```

Use it like this: `zsh lab/lab.sh up`, then `zsh lab/lab.sh push ./repo "a commit message"` (it replaces the repository's files with your folder and pushes one commit), `zsh lab/lab.sh wait` (waits for the newest run and lists its jobs), `zsh lab/lab.sh logs JOB_ID`, and finally `zsh lab/lab.sh down`. The Gitea web UI is on `http://127.0.0.1:21054` (user `asha`, password `fake-lab-pass-asha`, a fake lab value).

### Acceptance criteria
1. The workflow runs unchanged in the lab and on GitHub (no Gitea-only syntax).
2. `lint`, `test` and `scan` run in parallel; `build` has `needs:` on all three and is skipped when any fails.
3. Lint: hadolint on the Dockerfile and shellcheck on the scripts, as required gates.
4. Tests: the Dockerfile's test stage, so CI tests exactly what ships.
5. Scan: gitleaks over the **whole** history, and Trivy on the dependencies; HIGH or CRITICAL findings with a fix fail the job.
6. Build: the runtime image is built once, smoke-tested with `scripts/smoke.sh`, and scanned with Trivy.
7. Least privilege and hygiene: `permissions: contents: read`, a `concurrency` group that cancels stale runs, `timeout-minutes` on every job, every tool image pinned (Trivy by digest).
8. Prove the gates work: one run that fails on purpose (and why), then a green run.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 25 | Gates correct and ordered: parallel checks, build depends on them, failures stop the build |
| 20 | It ran: links or logs from a red run and a green run, and the red run failed for the stated reason |
| 20 | Supply chain: pinned tools and actions, minimal permissions, no secrets needed for a pull request |
| 15 | Speed: what runs in parallel, what's cached, total time measured |
| 20 | README: what each gate catches, what it doesn't, and how you'd add a push and a deploy |

### Stretch goals
- Push the image to a registry only on main, tagged with the commit SHA, and pass its digest to a deploy job.
- Cache the pip downloads or the BuildKit layers, and report the time saved.
- actionlint as a fifth gate.
- Pin `actions/checkout` to a full commit SHA, and add Dependabot or Renovate config to keep it current.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`.github/workflows/ci.yml`**

```yaml
# CI for course-search: four gates on every pull request and every push to main.
# lint, test and scan run in parallel; build runs only when all three pass.
name: ci
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  IMAGE: course-search

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: hadolint (Dockerfile)
        uses: docker://hadolint/hadolint:v2.15.1
        with:
          args: hadolint --no-color Dockerfile
      - name: shellcheck (scripts)
        uses: docker://koalaman/shellcheck:v0.11.0
        with:
          args: scripts/smoke.sh

  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: unit tests (the Dockerfile's test stage)
        run: docker build --target test -t "$IMAGE:test-${GITHUB_SHA::7}" .

  scan:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0               # the whole history: a secret in an old commit still leaks
      - name: gitleaks (any secret blocks)
        uses: docker://zricethezav/gitleaks:v8.30.1
        with:
          args: git --redact --no-banner -v .
      - name: trivy fs (HIGH or CRITICAL with a fix blocks)
        uses: docker://aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
        with:
          args: fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q .

  build:
    needs: [lint, test, scan]
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - name: build the runtime image once
        run: |
          docker build --build-arg APP_VERSION="${GITHUB_SHA::7}" -t "$IMAGE:${GITHUB_SHA::7}" .
          docker image inspect -f 'user={{.Config.User}} size={{.Size}}' "$IMAGE:${GITHUB_SHA::7}"
      - name: smoke test
        env:
          SMOKE_HOST: docker               # the CI Docker daemon publishes the test port
        run: scripts/smoke.sh "$IMAGE:${GITHUB_SHA::7}"
      - name: export the image for the scanner
        run: docker save -o image.tar "$IMAGE:${GITHUB_SHA::7}"
      - name: trivy image (HIGH or CRITICAL with a fix blocks)
        uses: docker://aquasec/trivy:0.76.0@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222
        with:
          args: image --input image.tar --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 -q
```

Gitea 28.1.0 read the file from `.github/workflows/` directly (the repository had no `.gitea/` folder). The `docker://` steps run the pinned tool images with the workspace mounted; the `run:` steps use the lab's separate Docker daemon through `DOCKER_HOST`.

**Red run 1, a staged bug.** The first push changed `words = set(q.lower().split())` to `words = set(q.split())`, so a search for "Docker basics" no longer matches the topic "docker" (commands run from the task folder; in this repository the staged copies are in `t04/solution/staged/` and the final one in `t04/solution/repo/`):

```text
$ zsh lab/lab.sh push solution/staged/repo-bug "search: split the query into words"
d74f76c search: split the query into words
```

```text
$ zsh lab/lab.sh wait
run 1 completed failure
1	lint	success	22:56:16-22:56:20
2	test	failure	22:56:16-22:56:46
3	scan	success	22:56:20-22:56:43
4	build	skipped	00:00:00-00:00:00
```

From the test job's log (`zsh lab/lab.sh logs 2`, timestamps cut):

```text
#18 1.191 >       assert r.json()["results"] == ["DevOps"]
#18 1.191 E       AssertionError: assert [] == ['DevOps']
…
#18 1.191 1 failed, 2 passed in 0.28s
…
1.191 >       assert r.json()["results"] == ["DevOps"]
1.191 E       AssertionError: assert [] == ['DevOps']
…
ERROR: failed to build: failed to solve: process "/bin/sh -c python -m pytest -q" did not complete successfully: exit code: 1
…
Job failed
```

**Red run 2, a staged lint failure.** After the green run below, on a freshly started lab (so the run number starts at 1 again), a push turned the CMD back into shell form. Only `lint` failed, and `build` was skipped:

```text
$ zsh lab/lab.sh push solution/staged/repo-lint "Dockerfile: simpler CMD"
a4b39cc Dockerfile: simpler CMD
$ zsh lab/lab.sh wait
run 1 completed failure
1	lint	failure	23:28:10-23:28:14
2	test	success	23:28:10-23:28:36
3	scan	success	23:28:14-23:28:32
4	build	skipped	00:00:00-00:00:00
```

```text
Dockerfile:44 DL3025 warning: Use arguments JSON notation for CMD and ENTRYPOINT arguments
##[error]Process completed with exit code 1.
…
Job failed
```

**Green run.** The fixed search:

```text
$ zsh lab/lab.sh push solution/repo "search: match words in any case"
5771b22 search: match words in any case
$ zsh lab/lab.sh wait
run 2 completed success
5	lint	success	22:57:09-22:57:13
6	test	success	22:57:09-22:57:18
7	scan	success	22:57:13-22:57:29
8	build	success	22:57:31-22:57:58
```

From the build job's log (timestamps cut):

```text
user=10001:10001 size=48692177
…
health: healthy
{"query":"docker","results":["DevOps"]}
…
│ image.tar (debian 13.7)                                                          │   debian   │        0        │
…
Job succeeded
```

The scan job's gitleaks step in the first run printed `no leaks found` over `1 commits scanned`, and its Trivy summary showed `requirements.txt` with 0 vulnerabilities.

**Trade-offs worth writing in the README:** tests run inside `docker build --target test` rather than on the runner's Python, so they use the exact base image and dependency versions that ship, at the cost of a slower first build; gitleaks needs `fetch-depth: 0`, or a secret in an old commit is invisible; the image is scanned from a `docker save` tarball because the scanner step runs outside the job's Docker daemon; and nothing here needs a secret, so the workflow is safe to run for pull requests from forks.

</details>

---

## Task 5 · A Terraform module with offline tests
**Time box: 2 to 3 hours · Difficulty: Medium · Course: [M04-L01 - IP Addresses, Subnets and CIDR](../networking/m04-l01-ip-addresses-subnets-and-cidr/), [M11-L02 - HCL Basics](../terraform/m11-l02-hcl-basics/), [M11-L04 - Modules](../terraform/m11-l04-modules/), [M11-L05 - Environments and Pipelines](../terraform/m11-l05-environments-and-pipelines/)**

### The brief

> **From the allcsvideos cloud team.** Every VPC we build uses the same subnet layout from the Module 4 network plan: three tiers (public, private, isolated), one /24 per tier per availability zone, at fixed offsets inside the VPC's /16 (public from 0, private from 10, isolated from 20). People keep getting it wrong by hand. Write a reusable module, `modules/subnet-plan`, that computes the layout and records one item per subnet, with input validation and tests that run in CI without any cloud credentials or network access. The AWS resources will come later; the layout logic must be right first.

**Inputs:** `environment` (dev, staging or prod), `vpc_cidr` (an IPv4 /16), `azs` (1 to 4 distinct zone names; prod needs at least 2), `tags` (must include `owner` and `cost-center`).
**Outputs:** `subnets` (a map keyed `<tier>-<az>` with tier, az and cidr), `cidrs_by_tier` (CIDRs per tier, in zone order), `names` (sorted names `allcs-<env>-<tier>-<az>`).

### Starter files

**`main.tf`** (the root that will use the module)

```hcl
# Root: the prod network plan from Module 4 (prod 10.0.0.0/16), three zones in ap-south-1.
module "prod" {
  source      = "./modules/subnet-plan"
  environment = "prod"
  vpc_cidr    = "10.0.0.0/16"
  azs         = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  tags        = { owner = "asha", cost-center = "platform" }
}

output "prod_private_cidrs" {
  value = module.prod.cidrs_by_tier["private"]
}
```

**`versions.tf`**

```hcl
terraform {
  required_version = ">= 1.9.0"
}
```

**`tests/acceptance.tftest.hcl`** (the reviewer's tests: keep them passing, and add your own)

```hcl
# acceptance.tftest.hcl: the reviewer's tests (offline, plan only). Keep them passing; add your own.
variables {
  environment = "staging"
  vpc_cidr    = "10.1.0.0/16"
  azs         = ["ap-south-1a", "ap-south-1b"]
  tags        = { owner = "asha", cost-center = "platform" }
}

run "layout_is_deterministic" {
  command = plan
  module { source = "./modules/subnet-plan" }

  assert {
    condition     = output.cidrs_by_tier["public"] == ["10.1.0.0/24", "10.1.1.0/24"]
    error_message = "public subnets should be 10.1.0.0/24 and 10.1.1.0/24"
  }
  assert {
    condition     = output.cidrs_by_tier["private"] == ["10.1.10.0/24", "10.1.11.0/24"]
    error_message = "private subnets should start at offset 10"
  }
  assert {
    condition     = length(output.subnets) == 6
    error_message = "2 zones x 3 tiers should give 6 subnets"
  }
}

run "rejects_unknown_environment" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { environment = "production" }
  expect_failures = [var.environment]
}
```

### Acceptance criteria
1. `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate`, `terraform test` and `terraform plan` all succeed in `hashicorp/terraform:1.16.6` started with `--network none`.
2. Each invalid input fails at plan time with a message that says what's wrong, and each rule has an `expect_failures` test.
3. The prod plan creates 9 items, with private CIDRs `10.0.10.0/24`, `10.0.11.0/24` and `10.0.12.0/24`.
4. Changing one subnet's CIDR replaces only that subnet's item.
5. The module has no provider blocks and documents its inputs and outputs.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 30 | Correct layout from `cidrsubnet()`, with deterministic keys (no list indexes that shift when a zone is added) |
| 25 | Validation that fails early with clear messages; cross-variable rules done right |
| 25 | Tests: positive and negative cases, and a test that would catch a wrong offset |
| 20 | Module interface and README: typed variables, descriptions, outputs, an example |

### Stretch goals
- A `check` or `postcondition` that fails if two subnets ever share a CIDR.
- An IPv6 option.
- A second module that turns `subnets` into real `aws_subnet` resources, tested with `mock_provider` so it still runs offline.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`modules/subnet-plan/variables.tf`**

```hcl
variable "environment" {
  description = "Environment name: dev, staging or prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "The VPC range, a /16 such as 10.0.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid IPv4 /16, for example 10.0.0.0/16."
  }
}

variable "azs" {
  description = "Availability zone names, one subnet of each tier per zone."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 1 && length(var.azs) <= 4 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs must list 1 to 4 distinct zone names."
  }

  validation {
    condition     = var.environment != "prod" || length(var.azs) >= 2
    error_message = "prod needs at least 2 availability zones."
  }
}

variable "tags" {
  description = "Extra tags. owner and cost-center are required."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in ["owner", "cost-center"] : contains(keys(var.tags), k)])
    error_message = "tags must include owner and cost-center."
  }
}
```

**`modules/subnet-plan/main.tf`**

```hcl
# subnet-plan: a deterministic subnet layout for one VPC (no cloud provider needed).
# Tier offsets in the /16: public 0-9, private 10-19, isolated 20-29, one /24 per zone.
locals {
  tier_offset = { public = 0, private = 10, isolated = 20 }

  subnets = merge([
    for tier, offset in local.tier_offset : {
      for i, az in var.azs : "${tier}-${az}" => {
        tier = tier
        az   = az
        cidr = cidrsubnet(var.vpc_cidr, 8, offset + i)
      }
    }
  ]...)

  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })
}

# One record per planned subnet. Changing a subnet's CIDR replaces only that record.
resource "terraform_data" "subnet" {
  for_each = local.subnets

  input            = merge(each.value, { name = "allcs-${var.environment}-${each.key}", tags = local.tags })
  triggers_replace = [each.value.cidr]
}

check "no_overlap_with_lab_range" {
  assert {
    condition     = !contains([for s in local.subnets : s.cidr], "10.0.205.0/24")
    error_message = "a subnet overlaps 10.0.205.0/24, which the local lab uses."
  }
}
```

**`modules/subnet-plan/outputs.tf`**

```hcl
output "subnets" {
  description = "Map of subnet key (tier-az) to its tier, zone and CIDR."
  value       = local.subnets
}

output "cidrs_by_tier" {
  description = "CIDRs grouped by tier, in zone order."
  value       = { for tier in keys(local.tier_offset) : tier => [for az in var.azs : local.subnets["${tier}-${az}"].cidr] }
}

output "names" {
  description = "Subnet names, sorted."
  value       = sort([for r in terraform_data.subnet : r.input.name])
}
```

**`modules/subnet-plan/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.9.0"
}
```

**`tests/subnet_plan.tftest.hcl`** (the reviewer's two runs, plus four more)

```hcl
# terraform test: runs offline (no providers, plan only).
variables {
  environment = "staging"
  vpc_cidr    = "10.1.0.0/16"
  azs         = ["ap-south-1a", "ap-south-1b"]
  tags        = { owner = "asha", cost-center = "platform" }
}

run "layout_is_deterministic" {
  command = plan
  module { source = "./modules/subnet-plan" }

  assert {
    condition     = output.cidrs_by_tier["public"] == ["10.1.0.0/24", "10.1.1.0/24"]
    error_message = "public subnets should be 10.1.0.0/24 and 10.1.1.0/24"
  }
  assert {
    condition     = output.cidrs_by_tier["private"] == ["10.1.10.0/24", "10.1.11.0/24"]
    error_message = "private subnets should start at offset 10"
  }
  assert {
    condition     = length(output.subnets) == 6
    error_message = "2 zones x 3 tiers should give 6 subnets"
  }
}

run "names_and_tags" {
  command = plan
  module { source = "./modules/subnet-plan" }

  assert {
    condition     = contains(output.names, "allcs-staging-isolated-ap-south-1b")
    error_message = "names follow allcs-<env>-<tier>-<az>"
  }
  assert {
    condition     = terraform_data.subnet["private-ap-south-1a"].input.tags["managed-by"] == "terraform"
    error_message = "every subnet carries managed-by = terraform"
  }
}

run "rejects_unknown_environment" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { environment = "production" }
  expect_failures = [var.environment]
}

run "rejects_bad_cidr" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { vpc_cidr = "10.1.0.0/20" }
  expect_failures = [var.vpc_cidr]
}

run "prod_needs_two_zones" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables {
    environment = "prod"
    azs         = ["ap-south-1a"]
  }
  expect_failures = [var.azs]
}

run "requires_owner_tag" {
  command = plan
  module { source = "./modules/subnet-plan" }
  variables { tags = { owner = "asha" } }
  expect_failures = [var.tags]
}
```

**Verification.** Every command ran as `docker run --rm --network none -v "$PWD":/work -w /work hashicorp/terraform:1.16.6 <command> -no-color`:

```text
$ terraform version
Terraform v1.16.6
on linux_arm64
exit 0
$ terraform fmt -check -recursive
exit 0
…
$ terraform validate
Success! The configuration is valid.

exit 0
$ terraform test
tests/subnet_plan.tftest.hcl... in progress
  run "layout_is_deterministic"... pass
  run "names_and_tags"... pass
  run "rejects_unknown_environment"... pass
  run "rejects_bad_cidr"... pass
  run "prod_needs_two_zones"... pass
  run "requires_owner_tag"... pass
tests/subnet_plan.tftest.hcl... tearing down
tests/subnet_plan.tftest.hcl... pass

Success! 6 passed, 0 failed.
exit 0
…
Plan: 9 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + prod_private_cidrs = [
      + "10.0.10.0/24",
      + "10.0.11.0/24",
      + "10.0.12.0/24",
    ]
…
```

The reviewer's file on its own against this module:

```text
$ terraform test   # the reference module against the starter acceptance tests
tests/acceptance.tftest.hcl... in progress
  run "layout_is_deterministic"... pass
  run "rejects_unknown_environment"... pass
tests/acceptance.tftest.hcl... tearing down
tests/acceptance.tftest.hcl... pass

Success! 2 passed, 0 failed.
exit 0
```

**Do the tests catch mistakes?** A staged copy with the private offset changed from 10 to 1, and the root's environment set to `production`:

```text
# staged: private offset changed from 10 to 1, root environment "production"
$ terraform test
tests/subnet_plan.tftest.hcl... in progress
  run "layout_is_deterministic"... fail

Error: Test assertion failed

  on tests/subnet_plan.tftest.hcl line 18, in run "layout_is_deterministic":
  18:     condition     = output.cidrs_by_tier["private"] == ["10.1.10.0/24", "10.1.11.0/24"]
    ├────────────────
    │ Diff:
    │ --- actual
    │ +++ expected
    │   [
    │ -   "10.1.1.0/24",
    │ -   "10.1.2.0/24"
    │ +   "10.1.10.0/24",
    │ +   "10.1.11.0/24"
    │   ]


private subnets should start at offset 10
  run "names_and_tags"... pass
  run "rejects_unknown_environment"... pass
  run "rejects_bad_cidr"... pass
  run "prod_needs_two_zones"... pass
  run "requires_owner_tag"... pass
tests/subnet_plan.tftest.hcl... tearing down
tests/subnet_plan.tftest.hcl... fail

Failure! 5 passed, 1 failed.
exit 1
$ terraform validate

Error: Invalid value for variable
…
```

The offset test caught a real collision: with offset 1, `private-ap-south-1a` gets `10.1.1.0/24`, the same CIDR as `public-ap-south-1b`. That's exactly what the stretch goal's overlap check is for.

**Trade-offs worth writing in the README:** `for_each` over string keys like `private-ap-south-1a` instead of `count`, so adding a zone never renumbers existing subnets; `terraform_data` with `triggers_replace` on the CIDR, so a layout change shows up in the plan as a replace of exactly that subnet; the cross-variable rule (prod needs two zones) lives in a validation block, which Terraform allows since 1.9 (hence `required_version`); and the module has no provider, so its tests need no credentials.

</details>

---

## Task 6 · A Helm chart with probes, resources, a PDB and an HPA
**Time box: 2 to 3 hours · Difficulty: Medium to Hard · Course: [M14-L03 - Health and Resources](../k8s/m14-l03-health-and-resources/), [M14-L04 - Autoscaling](../k8s/m14-l04-autoscaling/), [M15-L01 - Helm](../k8s/m15-l01-helm/), [M18-L04 - Kubernetes Security](../security/m18-l04-kubernetes-security/)**

### The brief

> **From the allcsvideos platform team.** Package `course-search` (the image from task 2) as a Helm chart that our clusters can run in a namespace that enforces the **restricted** Pod Security Standard. It must survive node maintenance without dropping below one ready pod, scale on CPU, and roll back by itself when a release doesn't become ready. Show it working on a local kind cluster.

### Starter files

A tool box image with the docker CLI, kind, kubectl and Helm. Save it as `k8s-tools/Dockerfile` (it's ready in [`m21-take-home/k8s-tools/`](m21-take-home/k8s-tools/Dockerfile)); the reference run built it with `docker build -q -t m21lab-tools:1.0 k8s-tools`:

```dockerfile
# syntax=docker/dockerfile:1
# Tool box for the Kubernetes take-home tasks: docker CLI, kind v0.33.0, kubectl v1.37.1 (checksums verified),
# Helm 4.3.1 (from the official alpine/helm image). The same versions as the Module 13-15 lessons.
FROM alpine/helm:4.3.1 AS helm
FROM docker:29.5.3-cli
ARG TARGETARCH
ARG KIND_VERSION=v0.33.0
ARG KUBECTL_VERSION=v1.37.1
ARG KIND_SHA_arm64=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2
ARG KIND_SHA_amd64=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
ARG KUBECTL_SHA_arm64=ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7
ARG KUBECTL_SHA_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
LABEL course=devops
RUN apk add --no-cache bash curl jq \
 && curl -fsSLo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${TARGETARCH} \
 && curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
 && if [ "$TARGETARCH" = arm64 ]; then KS=$KIND_SHA_arm64; CS=$KUBECTL_SHA_arm64; else KS=$KIND_SHA_amd64; CS=$KUBECTL_SHA_amd64; fi \
 && echo "$KS  /usr/local/bin/kind" | sha256sum -c - \
 && echo "$CS  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kind /usr/local/bin/kubectl
COPY --from=helm /usr/bin/helm /usr/local/bin/helm
WORKDIR /work
```

**`kind-cluster.yaml`** (one control plane, one worker)

```yaml
# kind cluster for the Kubernetes take-homes: one control plane, one worker. Longer leader-election timings keep a
# single control plane stable on a busy laptop (lab setting).
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatches:
- |
  kind: ClusterConfiguration
  controllerManager:
    extraArgs:
    - {name: enable-hostpath-provisioner, value: "true"}
    - {name: leader-elect-lease-duration, value: "90s"}
    - {name: leader-elect-renew-deadline, value: "60s"}
    - {name: leader-elect-retry-period, value: "10s"}
  scheduler:
    extraArgs:
    - {name: leader-elect-lease-duration, value: "90s"}
    - {name: leader-elect-renew-deadline, value: "60s"}
    - {name: leader-elect-retry-period, value: "10s"}
nodes:
- role: control-plane
- role: worker
```

Start the tool box with your task folder mounted and the Docker socket (kind creates the cluster's node containers on your Docker), then create the cluster and load your task 2 image. The reference run's commands, from the folder holding the task folders (pick your own names):

```bash
docker run -d --name m21lab-ops --label course=devops --network host --memory 512m -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD":/work -w /work m21lab-tools:1.0 sleep infinity
docker exec m21lab-ops kind create cluster --name m21lab-k8s --image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5 --config t06/solution/kind-cluster.yaml --wait 180s
docker exec m21lab-ops kind load docker-image m21lab-t02-app:1.0.0 --name m21lab-k8s
```

For the HPA you need metrics-server v0.9.0: apply its pinned release manifest, as in [M14-L04](../k8s/m14-l04-autoscaling/) (`https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml`) and add `--kubelet-insecure-tls`, which kind needs because its kubelet certificates have no IP SANs (a lab setting).

### Acceptance criteria
1. `helm lint --strict` passes, and a values schema rejects `image.tag=latest` and fewer than 2 replicas.
2. `helm template ... | kubectl apply --dry-run=server` succeeds in a namespace labelled `pod-security.kubernetes.io/enforce=restricted`, and the real install's pods are admitted there.
3. Startup, readiness and liveness probes, where liveness doesn't depend on the data file or any other dependency.
4. CPU and memory requests and a memory limit; an HPA from 2 to 5 replicas on CPU; a PDB that allows one pod down at a time.
5. `helm test` passes (a test pod calls `/search` through the Service).
6. Under load the HPA scales up; a node drain never takes the app below the PDB; an upgrade to a tag that doesn't exist rolls back by itself (`--rollback-on-failure`).

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 25 | Probes and resources that make sense for this app, and the reasoning in the README |
| 20 | Security context that passes the restricted standard without exceptions |
| 20 | Availability: PDB, rolling-update settings, preStop, topology spread |
| 20 | Evidence: HPA scaling, the drain and the rollback, with real output |
| 15 | Chart quality: helpers, labels, a schema, `helm test`, no hard-coded names |

### Stretch goals
- An HTTPRoute (Gateway API) template, off by default.
- A NetworkPolicy that allows only the gateway's namespace in, and DNS out.
- The same chart deployed by Argo CD from a Git repository, with one values file per environment.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`chart/course-search/Chart.yaml`**

```yaml
apiVersion: v2
name: course-search
description: The allcsvideos course-search API (take-home task 6)
type: application
version: 0.1.0
appVersion: "1.0.0"
```

**`values.yaml`**

```yaml
image:
  repository: m21lab-t02-app
  tag: "1.0.0"
  pullPolicy: IfNotPresent

replicaCount: 2

service:
  port: 80

resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits: {cpu: 250m, memory: 128Mi}

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70

pdb:
  enabled: true
  maxUnavailable: 1

# seconds the pod keeps serving after it is removed from the endpoints, before nginx/uvicorn get SIGTERM
preStopSleepSeconds: 5
```

**`values.schema.json`**

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["image", "replicaCount", "resources"],
  "properties": {
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": {"type": "string", "minLength": 1},
        "tag": {"type": "string", "minLength": 1, "not": {"const": "latest"}},
        "pullPolicy": {"enum": ["IfNotPresent", "Always", "Never"]}
      }
    },
    "replicaCount": {"type": "integer", "minimum": 2},
    "resources": {
      "type": "object",
      "required": ["requests", "limits"],
      "properties": {
        "requests": {"type": "object", "required": ["cpu", "memory"]},
        "limits": {"type": "object", "required": ["memory"]}
      }
    },
    "autoscaling": {
      "type": "object",
      "properties": {
        "minReplicas": {"type": "integer", "minimum": 2},
        "maxReplicas": {"type": "integer", "minimum": 2}
      }
    }
  }
}
```

**`templates/_helpers.tpl`**

```text
{{- define "cs.name" -}}{{ .Release.Name }}{{- end -}}
{{- define "cs.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
{{- define "cs.selector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

**`templates/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "cs.name" . }}
  labels: {{- include "cs.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  selector:
    matchLabels: {{- include "cs.selector" . | nindent 6 }}
  template:
    metadata:
      labels: {{- include "cs.labels" . | nindent 8 }}
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 20
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile: {type: RuntimeDefault}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: {{- include "cs.selector" . | nindent 14 }}
      containers:
        - name: api
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - {name: http, containerPort: 8000}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
          startupProbe:
            httpGet: {path: /health, port: http}
            periodSeconds: 2
            failureThreshold: 15
          readinessProbe:
            httpGet: {path: /health, port: http}
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            # the process only: /docs needs no data file, so a missing index never restarts the pod
            httpGet: {path: /docs, port: http}
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              sleep: {seconds: {{ .Values.preStopSleepSeconds }}}
          resources: {{- toYaml .Values.resources | nindent 12 }}
```

**`templates/service.yaml`**, **`templates/pdb.yaml`** and **`templates/hpa.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "cs.name" . }}
  labels: {{- include "cs.labels" . | nindent 4 }}
spec:
  selector: {{- include "cs.selector" . | nindent 4 }}
  ports:
    - {name: http, port: {{ .Values.service.port }}, targetPort: http}
```

```yaml
{{- if .Values.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "cs.name" . }}
  labels: {{- include "cs.labels" . | nindent 4 }}
spec:
  maxUnavailable: {{ .Values.pdb.maxUnavailable }}
  selector:
    matchLabels: {{- include "cs.selector" . | nindent 6 }}
{{- end }}
```

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "cs.name" . }}
  labels: {{- include "cs.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "cs.name" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: {type: Utilization, averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}}
{{- end }}
```

**`templates/tests/test-search.yaml`**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "cs.name" . }}-test
  labels: {{- include "cs.labels" . | nindent 4 }}
  annotations:
    helm.sh/hook: test
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: search
      image: busybox:1.37.0
      command: ["sh", "-c", "wget -qO- -T 5 http://{{ include "cs.name" . }}/search?q=docker | grep -q DevOps && echo search ok"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: [ALL]}
```

**`load.yaml`** (lab traffic for the HPA check)

```yaml
# load: 8 busybox loops calling the search endpoint (lab traffic for the HPA check)
apiVersion: v1
kind: Pod
metadata:
  name: load
  labels: {app: load}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: load
      image: busybox:1.37.0
      command: ["sh", "-c", "for i in 1 2 3 4 5 6 7 8; do (while true; do wget -qO- -T 2 http://cs/search?q=docker >/dev/null 2>&1; done) & done; wait"]
      resources: {requests: {cpu: 50m, memory: 16Mi}, limits: {cpu: 500m, memory: 32Mi}}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
```

**Verification**, on kind v0.33.0 with `kindest/node:v1.37.0` (the reference cluster was called `m21lab-k8s`). Lint, and the schema at work:

```text
$ helm lint --strict chart/course-search
==> Linting chart/course-search
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
exit 0
$ helm lint --strict chart/course-search --set image.tag=latest
Error: 1 chart(s) linted, 1 chart(s) failed
==> Linting chart/course-search
[INFO] Chart.yaml: icon is recommended
[ERROR] values.yaml: - at '/image/tag': 'not' failed

[ERROR] templates/: values don't meet the specifications of the schema(s) in the following chart(s):
course-search:
- at '/image/tag': 'not' failed


exit 1
```

Install into a restricted namespace, and `helm test`:

```text
$ kubectl create namespace allcs
namespace/allcs created
$ kubectl label namespace allcs pod-security.kubernetes.io/enforce=restricted
namespace/allcs labeled
$ helm template cs chart/course-search -n allcs | kubectl apply --dry-run=server -n allcs -f -
poddisruptionbudget.policy/cs created (server dry run)
service/cs created (server dry run)
deployment.apps/cs created (server dry run)
horizontalpodautoscaler.autoscaling/cs created (server dry run)
pod/cs-test created (server dry run)
$ helm upgrade --install cs chart/course-search -n allcs --rollback-on-failure --wait --timeout 3m
Release "cs" does not exist. Installing it now.
NAME: cs
LAST DEPLOYED: Wed Oct 21 23:01:47 2026
NAMESPACE: allcs
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
$ kubectl -n allcs get deploy,pods,svc,pdb,hpa -o wide
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                   SELECTOR
deployment.apps/cs   2/2     2            2           5s    api          m21lab-t02-app:1.0.0     app.kubernetes.io/instance=cs,app.kubernetes.io/name=course-search

NAME                      READY   STATUS    RESTARTS   AGE   IP           NODE                  NOMINATED NODE   READINESS GATES
pod/cs-78d9b8dfc6-rbb5k   1/1     Running   0          5s    10.244.1.5   m21lab-k8s-worker     <none>           <none>
pod/cs-78d9b8dfc6-rskhn   1/1     Running   0          5s    10.244.1.4   m21lab-k8s-worker     <none>           <none>

NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE   SELECTOR
service/cs   ClusterIP   10.96.213.114   <none>        80/TCP    5s    app.kubernetes.io/instance=cs,app.kubernetes.io/name=course-search

NAME                            MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/cs   N/A             1                 1                     5s

NAME                                     REFERENCE       TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/cs   Deployment/cs   cpu: <unknown>/70%   2         5         1          5s
$ helm test cs -n allcs
NAME: cs
LAST DEPLOYED: Wed Oct 21 23:01:47 2026
NAMESPACE: allcs
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE:     cs-test
Last Started:   Wed Oct 21 23:01:52 2026
Last Completed: Wed Oct 21 23:01:59 2026
Phase:          Succeeded
```

The HPA under load (8 busybox loops calling `/search`):

```text
$ kubectl -n allcs top pods; kubectl -n allcs get hpa cs
NAME                  CPU(cores)   MEMORY(bytes)   
cs-78d9b8dfc6-rbb5k   13m          33Mi            
cs-78d9b8dfc6-rskhn   47m          33Mi            
NAME   REFERENCE       TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
cs     Deployment/cs   cpu: <unknown>/70%   2         5         2          25s
$ kubectl -n allcs apply -f load.yaml
pod/load created
$ for i in $(seq 12); do date -u +%T; kubectl -n allcs get hpa cs --no-headers; sleep 20; done
23:02:12
cs    Deployment/cs   cpu: <unknown>/70%   2     5     2     25s
23:02:32
cs    Deployment/cs   cpu: <unknown>/70%   2     5     2     45s
23:02:52
cs    Deployment/cs   cpu: 347%/70%   2     5     2     65s
23:03:12
cs    Deployment/cs   cpu: 451%/70%   2     5     4     85s
23:03:32
cs    Deployment/cs   cpu: 274%/70%   2     5     5     105s
23:03:52
cs    Deployment/cs   cpu: 160%/70%   2     5     5     2m5s
23:04:12
cs    Deployment/cs   cpu: 196%/70%   2     5     5     2m25s
23:04:32
cs    Deployment/cs   cpu: 168%/70%   2     5     5     2m45s
23:04:52
cs    Deployment/cs   cpu: 114%/70%   2     5     5     3m5s
23:05:12
cs    Deployment/cs   cpu: 181%/70%   2     5     5     3m25s
23:05:32
cs    Deployment/cs   cpu: 116%/70%   2     5     5     3m46s
23:05:53
cs    Deployment/cs   cpu: 98%/70%   2     5     5     4m6s
```

A node drain with all 5 pods on the only worker:

```text
$ kubectl -n allcs get pdb cs
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
cs     N/A             1                 1                     5m8s
exit 0
$ kubectl drain m21lab-k8s-worker --ignore-daemonsets --delete-emptydir-data --timeout=40s
node/m21lab-k8s-worker cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/kindnet-lc8dq, kube-system/kube-proxy-nkjvk
evicting pod kube-system/metrics-server-84c99cb944-n5t6v
evicting pod allcs/cs-78d9b8dfc6-mfjps
evicting pod allcs/cs-78d9b8dfc6-5mptv
evicting pod allcs/cs-78d9b8dfc6-rbb5k
evicting pod allcs/cs-78d9b8dfc6-hfd9h
evicting pod allcs/cs-78d9b8dfc6-rskhn
error when evicting pods/"cs-78d9b8dfc6-mfjps" -n "allcs" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
error when evicting pods/"cs-78d9b8dfc6-rskhn" -n "allcs" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
error when evicting pods/"cs-78d9b8dfc6-5mptv" -n "allcs" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
error when evicting pods/"cs-78d9b8dfc6-rbb5k" -n "allcs" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/metrics-server-84c99cb944-n5t6v evicted
…
error: unable to drain node "m21lab-k8s-worker" due to error: [error when evicting pods/"cs-78d9b8dfc6-rskhn" -n "allcs": global timeout reached: 40s, error when evicting pods/"cs-78d9b8dfc6-5mptv" -n "allcs": global timeout reached: 40s, error when evicting pods/"cs-78d9b8dfc6-rbb5k" -n "allcs": global timeout reached: 40s, error when evicting pods/"cs-78d9b8dfc6-mfjps" -n "allcs": global timeout reached: 40s], continuing command...
There are pending nodes to be drained:
 m21lab-k8s-worker
error when evicting pods/"cs-78d9b8dfc6-rskhn" -n "allcs": global timeout reached: 40s
error when evicting pods/"cs-78d9b8dfc6-5mptv" -n "allcs": global timeout reached: 40s
error when evicting pods/"cs-78d9b8dfc6-rbb5k" -n "allcs": global timeout reached: 40s
error when evicting pods/"cs-78d9b8dfc6-mfjps" -n "allcs": global timeout reached: 40s
exit 1
$ kubectl -n allcs get pods -o wide
NAME                  READY   STATUS    RESTARTS   AGE     IP            NODE                  NOMINATED NODE   READINESS GATES
cs-78d9b8dfc6-5kcjb   0/1     Pending   0          41s     <none>        <none>                <none>           <none>
cs-78d9b8dfc6-5mptv   1/1     Running   0          4m34s   10.244.1.10   m21lab-k8s-worker     <none>           <none>
cs-78d9b8dfc6-mfjps   1/1     Running   0          4m49s   10.244.1.9    m21lab-k8s-worker     <none>           <none>
cs-78d9b8dfc6-rbb5k   1/1     Running   0          5m49s   10.244.1.5    m21lab-k8s-worker     <none>           <none>
cs-78d9b8dfc6-rskhn   1/1     Running   0          5m49s   10.244.1.4    m21lab-k8s-worker     <none>           <none>
exit 0
$ kubectl -n allcs get pdb cs
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
cs     N/A             1                 0                     5m49s
exit 0
…
```

The drain evicted one of the app's pods (and metrics-server), and the replacement stayed Pending: the control plane takes no workloads, so with one worker there was nowhere to go. The PDB then allowed 0 more disruptions, and drain gave up after its timeout instead of taking the app down. On a real cluster you'd add a node first.

A release with a tag that doesn't exist:

```text
$ helm upgrade cs chart/course-search -n allcs --set image.tag=1.0.1 --rollback-on-failure --wait --timeout 60s
level=WARN msg="upgrade failed" name=cs error="resource Deployment/allcs/cs not ready. status: InProgress, message: Updated: 1/5\ncontext deadline exceeded"
Error: UPGRADE FAILED: release cs failed, and has been rolled back due to rollback-on-failure being set: resource Deployment/allcs/cs not ready. status: InProgress, message: Updated: 1/5
context deadline exceeded
exit 1
$ helm history cs -n allcs
REVISION	UPDATED                 	STATUS    	CHART              	APP VERSION	DESCRIPTION                                                                                           
1       	Wed Oct 21 23:01:47 2026	superseded	course-search-0.1.0	1.0.0      	Install complete                                                                                      
2       	Wed Oct 21 23:07:42 2026	failed    	course-search-0.1.0	1.0.0      	Upgrade "cs" failed: resource Deployment/allcs/cs not ready. status: InProgress, message: Updated: ...
3       	Wed Oct 21 23:08:42 2026	deployed  	course-search-0.1.0	1.0.0      	Rollback to 1                                                                                         
exit 0
$ kubectl -n allcs get deploy cs -o wide
NAME   READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS   IMAGES                   SELECTOR
cs     5/5     5            5           6m56s   api          m21lab-t02-app:1.0.0     app.kubernetes.io/instance=cs,app.kubernetes.io/name=course-search
exit 0
```

**Trade-offs worth writing in the README:** liveness calls `/docs`, which FastAPI serves without touching the data file, while readiness calls `/health`, which fails when the index is missing, so a bad data file takes pods out of the Service without restart loops; the chart sets a 250m CPU limit; many teams leave CPU limits off because throttling hurts latency, but here the limit keeps the HPA demo bounded on a shared laptop, and the README should say which you'd choose in production; with the HPA enabled the Deployment has no `replicas` field, so Helm upgrades don't fight the autoscaler; and the preStop sleep uses the native `sleep` lifecycle action, so the image needs no shell.

</details>

---

## Task 7 · Instrument a service, and alert on its SLO
**Time box: 2 to 3 hours · Difficulty: Medium to Hard · Course: [M16-L02 - Metrics with Prometheus](../observability/m16-l02-metrics-with-prometheus/), [M16-L06 - Alerting](../observability/m16-l06-alerting/), [M17-L01 - SLIs, SLOs and Error Budgets](../observability/m17-l01-slis-slos-and-error-budgets/)**

### The brief

> **From the allcsvideos SRE team.** The catalog API has a new SLO: **99.9% of `GET /api/courses` requests succeed (not 5xx) over 30 days**. It has no metrics yet. Instrument it for Prometheus, write the recording rules for its SLI, and write multi-window, multi-burn-rate alerts that page for fast burns and open a ticket for slow burns, so we're woken up for real outages and never for a three-minute blip. Every alert must be unit-tested with `promtool` before we merge it.

### Starter files

**`app/catalog.py`** (not instrumented yet)

```python
"""catalog: the allcsvideos course-list API stand-in for the observability take-home (no real database).

GET /api/courses  the course list (fails with 503 for a share of requests: ERROR_RATE, default 0)
GET /healthz      liveness
Not instrumented yet: that is the task.
"""
import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ERROR_RATE = float(os.environ.get("ERROR_RATE", "0"))
COURSES = [{"id": "dsa"}, {"id": "devops"}, {"id": "genai"}]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            return self.reply(200, {"status": "ok"})
        if self.path == "/api/courses":
            time.sleep(random.uniform(0.005, 0.040))   # pretend database work
            if random.random() < ERROR_RATE:
                return self.reply(503, {"error": "database unavailable"})
            return self.reply(200, COURSES)
        return self.reply(404, {"error": "not found"})

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
```

**`app/Dockerfile`**

```dockerfile
FROM python:3.13.16-slim
RUN pip install --no-cache-dir prometheus-client==0.26.0 && useradd --uid 10001 app
COPY catalog.py /app/catalog.py
USER 10001
CMD ["python", "/app/catalog.py"]
```

### Acceptance criteria
1. The service exposes `/metrics` with `http_requests_total{route,status}`, a latency histogram `http_request_duration_seconds{route}` and `http_requests_in_flight`. Route labels are bounded (unknown paths share one label value).
2. The SLI's error ratio exists (as 0) before the first error, so alerts can be evaluated from the first scrape.
3. Recording rules for the error ratio over 5m, 30m, 1h, 2h, 6h, 1d and 3d, and a p95 latency.
4. Page alerts at 14.4x (1h and 5m) and 6x (6h and 30m), a ticket alert at 3x (1d and 2h) or 1x (3d and 6h), each with a runbook link; and an alert for a target that disappears.
5. `promtool check rules`, `promtool check config` and `promtool test rules` pass. The tests prove: no alert at baseline; 20% errors page; a 3-minute blip at 10% errors doesn't page; 0.5% errors for hours open a ticket and don't page; a missing target pages.
6. A Compose stack (the app, a load generator, Prometheus `v3.15.0`) where, with 20% errors injected, the page really fires in Prometheus, and ends after the fix.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 25 | Instrumentation: correct metric types, bounded labels, pre-created series |
| 25 | Burn-rate maths explained (why 14.4, why two windows) and implemented correctly |
| 25 | Tests that would fail if someone simplified the alerts, plus the live run |
| 15 | Alert hygiene: severities, team labels, runbook links, `for:` durations |
| 10 | README: what the on-call person sees and does when each alert fires |

### Stretch goals
- An Alertmanager config that routes `page` and `ticket` to different receivers, tested with `amtool config routes test`.
- A latency SLO (99% under 250 ms) from the histogram buckets, with its own burn-rate alerts.
- Generate the same rules with Sloth (`ghcr.io/slok/sloth:v0.16.0`) and compare them with yours.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`app/catalog.py`**

```python
"""catalog: the allcsvideos course-list API stand-in for the observability take-home (no real database).

GET /api/courses  the course list (fails with 503 for a share of requests: ERROR_RATE, default 0)
GET /healthz      liveness
GET /metrics      Prometheus metrics: http_requests_total, http_request_duration_seconds, http_requests_in_flight
"""
import json
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

ERROR_RATE = float(os.environ.get("ERROR_RATE", "0"))
COURSES = [{"id": "dsa"}, {"id": "devops"}, {"id": "genai"}]
ROUTES = {"/api/courses", "/healthz"}          # anything else is labelled "other": bounded cardinality

REQUESTS = Counter("http_requests_total", "HTTP requests handled.", ["route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP request duration.", ["route"],
                    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5))
IN_FLIGHT = Gauge("http_requests_in_flight", "HTTP requests being handled now.")

# pre-create the label sets we alert on, so ratios exist (as 0) before the first error
for code in ("200", "404", "503"):
    REQUESTS.labels("/api/courses", code)
LATENCY.labels("/api/courses")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            data = generate_latest()
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        route = self.path if self.path in ROUTES else "other"
        start = time.perf_counter()
        IN_FLIGHT.inc()
        try:
            status, body = self.handle_route()
        finally:
            IN_FLIGHT.dec()
        LATENCY.labels(route).observe(time.perf_counter() - start)
        REQUESTS.labels(route, str(status)).inc()
        self.reply(status, body)

    def handle_route(self):
        if self.path == "/healthz":
            return 200, {"status": "ok"}
        if self.path == "/api/courses":
            time.sleep(random.uniform(0.005, 0.040))   # pretend database work
            if random.random() < ERROR_RATE:
                return 503, {"error": "database unavailable"}
            return 200, COURSES
        return 404, {"error": "not found"}

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
```

**`prometheus/prometheus.yml`**

```yaml
global:
  scrape_interval: 5s
  evaluation_interval: 5s
rule_files: [slo-rules.yml, slo-alerts.yml]
scrape_configs:
  - job_name: catalog
    static_configs:
      - targets: ["app:8080"]
```

**`prometheus/slo-rules.yml`**

```yaml
# SLO: 99.9% of GET /api/courses requests succeed (not 5xx), rolling 30 days. Error budget: 0.1%.
groups:
  - name: catalog-slo-sli
    rules:
      - record: job:slo_errors_per_request:ratio_rate5m
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[5m])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[5m]))
      - record: job:slo_errors_per_request:ratio_rate30m
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[30m])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[30m]))
      - record: job:slo_errors_per_request:ratio_rate1h
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[1h])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[1h]))
      - record: job:slo_errors_per_request:ratio_rate2h
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[2h])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[2h]))
      - record: job:slo_errors_per_request:ratio_rate6h
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[6h])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[6h]))
      - record: job:slo_errors_per_request:ratio_rate1d
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[1d])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[1d]))
      - record: job:slo_errors_per_request:ratio_rate3d
        expr: sum by (job) (rate(http_requests_total{route="/api/courses", status=~"5.."}[3d])) / sum by (job) (rate(http_requests_total{route="/api/courses"}[3d]))
      - record: job:request_duration_seconds:p95_5m
        expr: histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket{route="/api/courses"}[5m])))
```

**`prometheus/slo-alerts.yml`**

```yaml
# Multi-window, multi-burn-rate alerts (the SRE workbook pattern). 0.001 = the error budget of a 99.9% SLO.
# Each pair needs the long window (is it significant?) AND the short window (is it still happening?).
groups:
  - name: catalog-slo-alerts
    rules:
      - alert: CatalogErrorBudgetBurn1h
        # 14.4x: 2% of a 30-day budget gone in 1 hour
        expr: job:slo_errors_per_request:ratio_rate1h > (14.4 * 0.001) and job:slo_errors_per_request:ratio_rate5m > (14.4 * 0.001)
        for: 2m
        labels: {severity: page, team: platform, window: 1h}
        annotations:
          summary: "catalog is burning its 30-day error budget fast"
          description: "GET /api/courses is failing faster than its 99.9% SLO allows."
          runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
      - alert: CatalogErrorBudgetBurn6h
        # 6x: 5% of the budget gone in 6 hours
        expr: job:slo_errors_per_request:ratio_rate6h > (6 * 0.001) and job:slo_errors_per_request:ratio_rate30m > (6 * 0.001)
        for: 2m
        labels: {severity: page, team: platform, window: 6h}
        annotations:
          summary: "catalog is burning its 30-day error budget fast"
          description: "GET /api/courses is failing faster than its 99.9% SLO allows."
          runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
      - alert: CatalogErrorBudgetSlowBurn
        # 3x over 1 day (10% of the budget), or 1x over 3 days (10%): a ticket, not a page
        expr: |
          (job:slo_errors_per_request:ratio_rate1d > (3 * 0.001) and job:slo_errors_per_request:ratio_rate2h > (3 * 0.001))
          or
          (job:slo_errors_per_request:ratio_rate3d > 0.001 and job:slo_errors_per_request:ratio_rate6h > 0.001)
        for: 1h
        labels: {severity: ticket, team: platform}
        annotations:
          summary: "catalog is slowly burning its 30-day error budget"
          description: "GET /api/courses is failing faster than its 99.9% SLO allows."
          runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
      - alert: CatalogScrapeMissing
        # a dead target has no errors at all: without this, the SLO alerts above stay silent
        expr: up{job="catalog"} == 0 or absent(up{job="catalog"})
        for: 2m
        labels: {severity: page, team: platform}
        annotations:
          summary: "Prometheus cannot scrape catalog"
          description: "No catalog metrics for 2 minutes, so the SLO alerts cannot fire."
          runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
```

**`prometheus/slo-tests.yml`**

```yaml
# promtool test rules slo-tests.yml : 10 requests/s, one sample per minute (600 requests per minute)
rule_files: [slo-rules.yml, slo-alerts.yml]
evaluation_interval: 1m
tests:
  - name: baseline, no errors, no alerts
    interval: 1m
    input_series:
      - {series: 'up{job="catalog",instance="app:8080"}', values: '1x120'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="200"}', values: '0+600x120'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="503"}', values: '0x120'}
    alert_rule_test:
      - {eval_time: 2h, alertname: CatalogErrorBudgetBurn1h, exp_alerts: []}
      - {eval_time: 2h, alertname: CatalogErrorBudgetBurn6h, exp_alerts: []}
      - {eval_time: 2h, alertname: CatalogErrorBudgetSlowBurn, exp_alerts: []}
      - {eval_time: 2h, alertname: CatalogScrapeMissing, exp_alerts: []}

  - name: 20% errors for 30 minutes pages, and each page ends when its short window is clean
    interval: 1m
    input_series:
      - {series: 'up{job="catalog",instance="app:8080"}', values: '1x150'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="200"}', values: '0+600x60 36480+480x29 51000+600x59'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="503"}', values: '0x60 120+120x29 3600x59'}
    promql_expr_test:
      - expr: job:slo_errors_per_request:ratio_rate5m
        eval_time: 75m
        exp_samples: [{labels: 'job:slo_errors_per_request:ratio_rate5m{job="catalog"}', value: 0.2}]
    alert_rule_test:
      - {eval_time: 62m, alertname: CatalogErrorBudgetBurn1h, exp_alerts: []}
      - eval_time: 75m
        alertname: CatalogErrorBudgetBurn1h
        exp_alerts:
          - exp_labels: {job: catalog, severity: page, team: platform, window: 1h}
            exp_annotations:
              summary: "catalog is burning its 30-day error budget fast"
              description: "GET /api/courses is failing faster than its 99.9% SLO allows."
              runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
      # 10 minutes after recovery the 5m window is clean, so the 1h page has ended ...
      - {eval_time: 100m, alertname: CatalogErrorBudgetBurn1h, exp_alerts: []}
      # ... but the 30m short window still holds errors, so the 6h page is still firing
      - eval_time: 100m
        alertname: CatalogErrorBudgetBurn6h
        exp_alerts:
          - exp_labels: {job: catalog, severity: page, team: platform, window: 6h}
            exp_annotations:
              summary: "catalog is burning its 30-day error budget fast"
              description: "GET /api/courses is failing faster than its 99.9% SLO allows."
              runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
      - {eval_time: 125m, alertname: CatalogErrorBudgetBurn6h, exp_alerts: []}

  - name: a 3-minute blip at 10% errors does not page
    interval: 1m
    input_series:
      - {series: 'up{job="catalog",instance="app:8080"}', values: '1x90'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="200"}', values: '0+600x60 36540+540x2 37620+600x27'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="503"}', values: '0x60 60+60x2 180x27'}
    alert_rule_test:
      - {eval_time: 70m, alertname: CatalogErrorBudgetBurn1h, exp_alerts: []}
      - {eval_time: 70m, alertname: CatalogErrorBudgetBurn6h, exp_alerts: []}

  - name: 0.5% errors for hours opens a ticket, not a page
    interval: 1m
    input_series:
      - {series: 'up{job="catalog",instance="app:8080"}', values: '1x180'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="200"}', values: '0+597x180'}
      - {series: 'http_requests_total{job="catalog",route="/api/courses",status="503"}', values: '0+3x180'}
    alert_rule_test:
      - {eval_time: 30m, alertname: CatalogErrorBudgetSlowBurn, exp_alerts: []}
      - eval_time: 2h
        alertname: CatalogErrorBudgetSlowBurn
        exp_alerts:
          - exp_labels: {job: catalog, severity: ticket, team: platform}
            exp_annotations:
              summary: "catalog is slowly burning its 30-day error budget"
              description: "GET /api/courses is failing faster than its 99.9% SLO allows."
              runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
      - {eval_time: 2h, alertname: CatalogErrorBudgetBurn1h, exp_alerts: []}
      - {eval_time: 2h, alertname: CatalogErrorBudgetBurn6h, exp_alerts: []}

  - name: a target that stops answering pages, because its SLO alerts cannot
    interval: 1m
    input_series:
      - {series: 'up{job="catalog",instance="app:8080"}', values: '1x10 0x10'}
    alert_rule_test:
      - eval_time: 15m
        alertname: CatalogScrapeMissing
        exp_alerts:
          - exp_labels: {job: catalog, instance: "app:8080", severity: page, team: platform}
            exp_annotations:
              summary: "Prometheus cannot scrape catalog"
              description: "No catalog metrics for 2 minutes, so the SLO alerts cannot fire."
              runbook_url: "https://runbooks.allcsvideos.example/catalog-error-budget"
```

**`compose.yaml`**, **`load.py`** and **`alerts.py`** (a small reader for Prometheus's alerts API, run in a `python:3.13.16-slim` container on the stack's network)

```yaml
name: m21lab-t07
services:
  app:
    build: ./app
    image: m21lab-t07-app:1.0
    environment:
      ERROR_RATE: ${ERROR_RATE:-0}
    labels: {course: devops}
    mem_limit: 128m
  load:
    image: python:3.13.16-slim
    command: ["python", "/load.py"]
    volumes: ["./load.py:/load.py:ro"]
    depends_on: [app]
    labels: {course: devops}
    mem_limit: 64m
  prometheus:
    image: prom/prometheus:v3.15.0
    volumes: ["./prometheus:/etc/prometheus:ro"]
    ports: ["127.0.0.1:21052:9090"]
    labels: {course: devops}
    mem_limit: 256m
```

```python
"""load: about 10 requests per second to the catalog, forever (lab traffic generator)."""
import time
import urllib.error
import urllib.request

while True:
    try:
        urllib.request.urlopen("http://app:8080/api/courses", timeout=2).read()
    except (urllib.error.URLError, OSError):
        pass
    time.sleep(0.1)
```

```python
"""alerts.py: print Prometheus's active alerts as one line each (state, name, labels, since)."""
import json
import sys
import urllib.request

url = sys.argv[1] if len(sys.argv) > 1 else "http://prometheus:9090"
data = json.load(urllib.request.urlopen(url + "/api/v1/alerts", timeout=5))["data"]["alerts"]
for a in sorted(data, key=lambda a: a["labels"]["alertname"]):
    l = a["labels"]
    print(f'{a["state"]:8} {l["alertname"]:28} severity={l["severity"]:7} since {a["activeAt"][11:19]}Z')
if not data:
    print("no active alerts")
```

**Verification.** promtool, run from `prom/prometheus:v3.15.0` with `--entrypoint promtool --network none`:

```text
…
$ promtool check rules slo-rules.yml slo-alerts.yml
Checking slo-rules.yml
  SUCCESS: 8 rules found

Checking slo-alerts.yml
  SUCCESS: 4 rules found

exit 0
$ promtool check config prometheus.yml
Checking prometheus.yml
  SUCCESS: 2 rule files found
 SUCCESS: prometheus.yml is valid prometheus config file syntax

Checking slo-rules.yml
  SUCCESS: 8 rules found

Checking slo-alerts.yml
  SUCCESS: 4 rules found

exit 0
$ promtool test rules slo-tests.yml
  SUCCESS

exit 0
```

**Would the tests catch a simplified alert?** A staged copy replaced the 14.4x rule with a naive single-window rule, `ratio_rate5m > 0.001`:

```text
# staged: CatalogErrorBudgetBurn1h replaced by a naive single-window rule: ratio_rate5m > 0.001
$ promtool test rules slo-tests.yml
  FAILED:
    name: 0.5% errors for hours opens a ticket, not a page,
    alertname: CatalogErrorBudgetBurn1h, time: 2h, 
        exp:[], 
        got:[
            0:
              Labels:{alertname="CatalogErrorBudgetBurn1h", job="catalog", severity="page", team="platform", window="1h"}
              Annotations:{description="GET /api/courses is failing faster than its 99.9% SLO allows.", runbook_url="https://runbooks.allcsvideos.example/catalog-error-budget", summary="catalog is burning its 30-day error budget fast"}
            ]


exit 1
```

The live run: `ERROR_RATE=0.2 docker compose up -d --build` (the app's `http_requests_created` timestamp, 1792622314, is 22:38:34 UTC), then:

```text
# 1) ERROR_RATE=0.2 since the app started at 22:38:34 UTC (its http_requests_created timestamp)
$ date -u +%T; docker run --rm --network m21lab-t07_default -v "$PWD/alerts.py:/alerts.py:ro" python:3.13.16-slim python /alerts.py
22:43:28
firing   CatalogErrorBudgetBurn1h     severity=page    since 22:38:54Z
firing   CatalogErrorBudgetBurn6h     severity=page    since 22:38:54Z
pending  CatalogErrorBudgetSlowBurn   severity=ticket  since 22:38:54Z
$ docker run --rm --network m21lab-t07_default curlimages/curl:8.17.0 -s "http://prometheus:9090/api/v1/query?query=job:slo_errors_per_request:ratio_rate1h"
{"status":"success","data":{"resultType":"vector","result":[{"metric":{"__name__":"job:slo_errors_per_request:ratio_rate1h","job":"catalog"},"value":[1792622610.071,"0.20102611940298507"]}]}}
# 2) the fix: ERROR_RATE=0
$ ERROR_RATE=0 docker compose up -d app
 Container m21lab-t07-app-1 Starting 
 Container m21lab-t07-app-1 Started 
22:43:32
```

Then every 30 seconds after the fix:

```text
22:44:10 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:44:42 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:45:13 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:45:44 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:46:15 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:46:46 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:47:18 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:47:49 firing/CatalogErrorBudgetBurn1h firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
22:48:20 firing/CatalogErrorBudgetBurn6h pending/CatalogErrorBudgetSlowBurn 
```

Both page alerts became active (pending) at 22:38:54, 20 seconds after the app started, and fired after their 2-minute `for:`: a rate over a 1-hour window with only seconds of data is simply the rate so far, so on a fresh Prometheus the long window protects nothing for its first hour. The 1h page ended between 4 and 5 minutes after the fix, once the 5m window was clean. The 6h page kept firing, because its 30-minute short window still held errors: the unit test shows it ending once that window is clean.

**Trade-offs worth writing in the README:** the two page alerts are separate rules, so the on-call person can see which window fired and you can inhibit one with the other; the SLI counts only `/api/courses`, not health checks or scrapes, because those aren't user requests; and `CatalogScrapeMissing` exists because a dead target has no errors at all, so the SLO alerts would stay silent during a full outage.

</details>

---

## Task 8 · Troubleshooting take-home: four broken scenarios, diagnosed and written up
**Time box: 3 hours · Difficulty: Hard · Course: [M20-B03 - Troubleshooting Labs](../capstones/m20-b03-troubleshooting-labs/), [M04-L05 - The Troubleshooting Toolbox](../networking/m04-l05-the-troubleshooting-toolbox/), [M14-L06 - Troubleshooting Kubernetes](../k8s/m14-l06-troubleshooting-kubernetes/), [M17-L02 - Incident Response](../observability/m17-l02-incident-response/)**

### The brief

> **From the allcsvideos SRE team.** Our troubleshooting round is a take-home. A colleague will inject four faults, one at a time, into the lab from Module 20, build 3, without telling you which. For each one: find the cause, fix it the way you would in production, verify it as a user, and keep timestamped notes. Then send us an incident write-up per scenario: symptom, impact, root cause, the evidence that proves it, the fix, how you verified it, and what would prevent it next time. We grade the write-ups, not just whether the lab is green at the end.

### Starter files

The troubleshooting-labs harness from [M20-B03 - Troubleshooting Labs](../capstones/m20-b03-troubleshooting-labs/) (its README explains the stack, `break.sh`, `reset.sh`, `note` and `score`). Your copy needs its own prefix and subnet so it can't collide with anything else on your machine. A ready copy using `m21lab-tl` and `10.0.205.0/24` is in [`m21-take-home/t08/troubleshooting-labs/`](m21-take-home/t08/troubleshooting-labs/README.md). Run it from `m21-take-home/t08`.

> Using the M20-B03 lab directly instead? It already takes its prefix from `P`: run `P=m21lab-tl bash ../capstones/m20-b03-troubleshooting-labs/lab.sh up`. It still uses the 10.0.203.0/24 subnet, so run that lab's `down` first if it is up.

Then `zsh troubleshooting-labs/lab.sh up` (1 minute 41 seconds on the reference run) ends with every check healthy:

```text
…
lab up
check                              result
web-01 /api/courses (TLS)          200
db-01 record (from web-01)         10.0.205.20
web-01 /var/log/allcs used           1%
db-01 client connections           1
pod catalog-6cbd6b6df7-f8tvg       1/1 Running restarts=0
pod catalog-6cbd6b6df7-zlccg       1/1 Running restarts=0
pod client                         1/1 Running restarts=0
pod thumbs-656b5cbc5d-kqdxh        1/1 Running restarts=0
catalog Service (in cluster)       {"version": "1.0", "pod": "catalog-6cbd6b6df7-zlccg", "cours
zsh troubleshooting-labs/lab.sh up  0.74s user 0.67s system 1% cpu 1:40.73 total
```

**Rules:** a colleague (or a random number) picks four scenarios and runs `./break.sh N` for each, telling you only the hint it prints, like an alert. Don't read `break.sh` or `scenarios.md` first. Write a `note "S<n> symptom: ..."`, `note "S<n> cause: ..."` and `note "S<n> fixed: ..."` line as you go, then `score`. Reset with `./reset.sh N` before the next one.

### Acceptance criteria
1. Four scenarios, each with a symptom, cause and fixed note, and a `score` table.
2. Each fix is the production fix, made at the source of truth where there is one (a manifest in git, the zone file, the job), not only a live patch.
3. Each write-up contains the evidence: the command and the line of output that proves the cause.
4. Each write-up has at least one prevention item that is a system change (an alert, a test, a guardrail), not "be more careful".
5. `lab.sh down`, then `lab.sh check` prints nothing.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 30 | Method: user-side symptom first, read-only checks before changes, one change at a time |
| 25 | Evidence: the cause is proven by output, not guessed |
| 20 | Fix quality: mitigation first where users are hurt, then the real fix at the source |
| 15 | Prevention items that would really have caught it earlier |
| 10 | Clear, blameless write-ups with a timeline |

### Stretch goals
- Do all ten scenarios, and compare your diagnose times across them.
- Add an eleventh scenario to the harness (its README explains how), with a card, and have a friend play it.
- Turn one write-up into a runbook page your team could follow at 3 a.m.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

The reference run played scenarios 2, 4, 8 and 9 on 22 October 2026 (UTC times). Its diagnosis was scripted from the scenario cards, so the timings below are a floor, not a target: a real first attempt takes minutes per scenario, not seconds.

**Scenario 2.** The hint: "debug logging was left on".

```text
asha@ops:~$ curl -s -w " %{http_code} %{time_total}s\n" https://www.allcsvideos.test/api/courses
{"error": "internal error"}
 500 0.019238s
asha@ops:~$ note "S2 symptom: /api/courses answers 500"
23:15:19 S2 symptom: /api/courses answers 500
asha@web-01:~$ sudo journalctl -u allcs-api -n 2 --no-pager -o cat
allcs-api listening on 127.0.0.1:8080, database db-01.allcsvideos.test
log write failed: [Errno 28] No space left on device
asha@web-01:~$ df -h /var/log/allcs
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M   64M     0 100% /var/log/allcs
asha@web-01:~$ sudo du -sh /var/log/allcs/* | sort -h
4.0K	/var/log/allcs/api.log
64M	/var/log/allcs/api-debug.log
asha@web-01:~$ sudo lsof /var/log/allcs/api-debug.log; echo "lsof exit $?"
lsof exit 1
asha@ops:~$ note "S2 cause: api-debug.log (forgotten debug logging) filled the 64M log disk"
23:15:19 S2 cause: api-debug.log (forgotten debug logging) filled the 64M log disk
asha@web-01:~$ sudo truncate -s 0 /var/log/allcs/api-debug.log
asha@web-01:~$ df -h /var/log/allcs
Filesystem      Size  Used Avail Use% Mounted on
tmpfs            64M  4.0K   64M   1% /var/log/allcs
asha@ops:~$ curl -s -w " %{http_code} %{time_total}s\n" https://www.allcsvideos.test/api/courses
{"courses": ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"]}
 200 0.015888s
asha@ops:~$ note "S2 fixed: debug log truncated, disk back to low use, /api/courses 200"
23:15:20 S2 fixed: debug log truncated, disk back to low use, /api/courses 200
```

Write-up: **symptom** every `/api/courses` request answered 500; **impact** all students, course list down; **cause** a debug log left switched on filled the 64 MB log disk, and the API fails when it can't write its log (`Errno 28` in the journal, `df` at 100%, `du` points at `api-debug.log`); **fix** nobody held the file open (`lsof` exit 1), so `truncate -s 0` freed the space at once, without restarting anything; **verified** `df` at 1% and a 200 from the user side; **prevent** logrotate with `maxsize` on that folder, debug logging that switches itself off after a set time, an alert at 80% disk use, and an app that keeps serving when its log write fails.

**Scenario 4.** The hint: "thumbs memory settings changed".

```text
asha@ops:~$ kubectl exec client -- wget -qO- -T 3 http://thumbs/; echo
wget: can't connect to remote host (10.96.223.210): Connection refused
command terminated with exit code 1

asha@ops:~$ kubectl get pods -l app=thumbs
NAME                     READY   STATUS      RESTARTS      AGE
thumbs-97b5745df-9t4tq   0/1     OOMKilled   2 (15s ago)   16s
asha@ops:~$ note "S4 symptom: thumbs refuses connections, its pod keeps restarting"
23:16:14 S4 symptom: thumbs refuses connections, its pod keeps restarting
asha@ops:~$ P=$(kubectl get pods -l app=thumbs --sort-by=.metadata.creationTimestamp -o name | tail -1); kubectl describe $P | grep -A6 "Last State"
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 21 Oct 2026 23:15:59 +0000
      Finished:     Wed, 21 Oct 2026 23:15:59 +0000
    Ready:          False
    Restart Count:  2
asha@ops:~$ kubectl get deploy thumbs -o jsonpath="{.spec.template.spec.containers[0].resources}{\"\n\"}"
{"limits":{"memory":"48Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}
asha@ops:~$ kubectl logs deploy/thumbs --previous --tail 3
unable to retrieve container logs for containerd://19c05fbeb585dfebbb0dcdab96c47c3b4dca16d788f7aa0b34bbf01da06f3c80asha@ops:~$ git -C allcsvideos-ops log --oneline -1 -- k8s/20-thumbs.yaml; grep -A3 "resources:" allcsvideos-ops/k8s/20-thumbs.yaml
876fbf9 ops repo: runbooks, inventory, nginx and kubernetes config
        resources:
          requests: {cpu: 10m, memory: 96Mi}
          limits: {memory: 128Mi}
---
asha@ops:~$ note "S4 cause: OOMKilled (exit 137): limit 48Mi, the repo says 128Mi"
23:16:15 S4 cause: OOMKilled (exit 137): limit 48Mi, the repo says 128Mi
asha@ops:~$ kubectl apply -f allcsvideos-ops/k8s/20-thumbs.yaml
deployment.apps/thumbs configured
service/thumbs unchanged
asha@ops:~$ kubectl rollout status deploy/thumbs --timeout=120s
Waiting for deployment "thumbs" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "thumbs" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "thumbs" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "thumbs" rollout to finish: 0 of 1 updated replicas are available...
deployment "thumbs" successfully rolled out
asha@ops:~$ kubectl get pods -l app=thumbs
NAME                      READY   STATUS    RESTARTS   AGE
thumbs-656b5cbc5d-klxns   1/1     Running   0          1s
asha@ops:~$ kubectl exec client -- wget -qO- -T 3 http://thumbs/; echo
{"version": "1.0", "pod": "thumbs-656b5cbc5d-klxns", "courses": ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"]}

asha@ops:~$ note "S4 fixed: manifest from git re-applied (limit 128Mi), 0 restarts, thumbs answers"
23:16:17 S4 fixed: manifest from git re-applied (limit 128Mi), 0 restarts, thumbs answers
```

Write-up: **symptom** the thumbs Service refused connections and its only pod was restarting; **cause** OOMKilled, exit code 137, after someone set its memory limit to 48Mi, while the manifest in git says 128Mi (`logs --previous` failed because the crashed container was already gone, so the evidence is `describe`'s Last State); **fix** re-apply the manifest from git, which also removes the drift; **verified** 0 restarts and a real answer through the Service; **prevent** limits set from the measured peak plus headroom, an alert on OOM kills and restart rate, a single replica no longer acceptable for a user-facing service (add a PDB and a second replica), and manual `kubectl set` on production blocked in favour of GitOps.

**Scenario 8.** The hint: "catalog release 1.0.1 deployed".

```text
asha@ops:~$ kubectl rollout status deploy/catalog --timeout=10s
Waiting for deployment "catalog" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
asha@ops:~$ kubectl get pods -l app=catalog
NAME                       READY   STATUS         RESTARTS   AGE
catalog-6cbd6b6df7-f8tvg   1/1     Running        0          2m25s
catalog-6cbd6b6df7-zlccg   1/1     Running        0          2m25s
catalog-ff9f4bd5b-h66dc    0/1     ErrImagePull   0          40s
asha@ops:~$ note "S8 symptom: catalog rollout stuck, the new pod does not start, old pods still serve"
23:17:06 S8 symptom: catalog rollout stuck, the new pod does not start, old pods still serve
asha@ops:~$ P=$(kubectl get pods -l app=catalog --sort-by=.metadata.creationTimestamp -o name | tail -1); kubectl events --for $P --types=Warning | tail -4
LAST SEEN           TYPE      REASON   OBJECT                        MESSAGE
25s (x2 over 39s)   Warning   Failed   Pod/catalog-ff9f4bd5b-h66dc   Failed to pull image "m21lab-tl-api:1.0.1": failed to pull and unpack image "docker.io/library/m21lab-tl-api:1.0.1": failed to resolve reference "docker.io/library/m21lab-tl-api:1.0.1": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
25s (x2 over 39s)   Warning   Failed   Pod/catalog-ff9f4bd5b-h66dc   Error: ErrImagePull
10s (x2 over 38s)   Warning   Failed   Pod/catalog-ff9f4bd5b-h66dc   Error: ImagePullBackOff
asha@ops:~$ kubectl rollout history deploy/catalog
deployment.apps/catalog 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>

asha@ops:~$ docker exec m21lab-tl-control-plane crictl images | grep -E "IMAGE|m21lab-tl-api"
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/m21lab-tl-api                 1.0                  5e6a94f4b5d44       22.6MB
asha@ops:~$ note "S8 cause: image m21lab-tl-api:1.0.1 was never built or pushed, only 1.0 exists"
23:17:07 S8 cause: image m21lab-tl-api:1.0.1 was never built or pushed, only 1.0 exists
asha@ops:~$ kubectl rollout undo deploy/catalog 2>/dev/null
deployment.apps/catalog rolled back
asha@ops:~$ kubectl rollout status deploy/catalog --timeout=120s
deployment "catalog" successfully rolled out
asha@ops:~$ kubectl get pods -l app=catalog
NAME                       READY   STATUS        RESTARTS   AGE
catalog-6cbd6b6df7-f8tvg   1/1     Running       0          2m26s
catalog-6cbd6b6df7-zlccg   1/1     Running       0          2m26s
catalog-ff9f4bd5b-h66dc    0/1     Terminating   0          41s
asha@ops:~$ kubectl exec client -- wget -qO- -T 3 http://catalog/courses; echo
{"version": "1.0", "pod": "catalog-6cbd6b6df7-f8tvg", "courses": ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"]}

asha@ops:~$ note "S8 fixed: rollout undo to 1.0, 2/2 ready, catalog answers"
23:17:07 S8 fixed: rollout undo to 1.0, 2/2 ready, catalog answers
```

Write-up: **symptom** the release never finished, the new pod sat in `ErrImagePull`, and users were fine because the rolling update kept both old pods; **cause** the image `m21lab-tl-api:1.0.1` was never built (the node only has `1.0`), and a name without a registry is looked up on Docker Hub, hence "pull access denied, repository does not exist"; **fix** `rollout undo` back to the working revision; **verified** 2 of 2 ready on 1.0 and the Service answers; **prevent** deploy only images CI pushed, by digest, and fail the pipeline on `kubectl rollout status` with a timeout so a stuck rollout is a red build, not a surprise.

**Scenario 9.** The hint: "the nightly report job started".

```text
asha@ops:~$ curl -s -w " %{http_code} %{time_total}s\n" https://www.allcsvideos.test/api/courses
{"error": "database unavailable"}
 503 0.021042s
asha@ops:~$ note "S9 symptom: /api/courses answers 503 fast"
23:17:24 S9 symptom: /api/courses answers 503 fast
asha@web-01:~$ sudo journalctl -u allcs-api -n 1 --no-pager -o cat
database error: connection to server at "db-01.allcsvideos.test" (10.0.205.20), port 5432 failed: FATAL:  remaining connection slots are reserved for roles with the SUPERUSER attribute
asha@ops:~$ psql -h db-01.allcsvideos.test -U postgres -d allcs -c "SELECT usename, application_name, state, count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1, 2, 3 ORDER BY 4 DESC"
  usename  | application_name | state  | count 
-----------+------------------+--------+-------
 allcs_app | nightly-report   | idle   |    17
 postgres  | psql             | active |     1
(2 rows)

asha@ops:~$ psql -h db-01.allcsvideos.test -U postgres -d allcs -tAc "SHOW max_connections"
20
asha@ops:~$ note "S9 cause: nightly-report holds idle connections; max_connections=20 is used up"
23:17:24 S9 cause: nightly-report holds idle connections; max_connections=20 is used up
asha@web-01:~$ systemctl status allcs-report --no-pager | head -4
● allcs-report.service - allcsvideos nightly course report
     Loaded: loaded (/etc/systemd/system/allcs-report.service; static)
     Active: active (running) since Wed 2026-10-21 23:17:15 UTC; 8s ago
   Main PID: 525 (python3)
asha@web-01:~$ sudo systemctl stop allcs-report
asha@ops:~$ psql -h db-01.allcsvideos.test -U postgres -d allcs -tAc "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend'"
1
asha@ops:~$ curl -s -w " %{http_code} %{time_total}s\n" https://www.allcsvideos.test/api/courses
{"courses": ["DSA", "System Design", "DevOps", "GenAI", "Spring Boot"]}
 200 0.012618s
asha@ops:~$ note "S9 fixed: report job stopped, its connections closed, /api/courses 200"
23:17:24 S9 fixed: report job stopped, its connections closed, /api/courses 200
asha@ops:~$ score
       diagnose        fix
S2          0s         1s
S4          1s         2s
S8          1s         0s
S9          0s         0s
all         2s         3s
asha@ops:~$ cat ~/incident/notes.log
23:15:19 S2 symptom: /api/courses answers 500
23:15:19 S2 cause: api-debug.log (forgotten debug logging) filled the 64M log disk
23:15:20 S2 fixed: debug log truncated, disk back to low use, /api/courses 200
23:16:14 S4 symptom: thumbs refuses connections, its pod keeps restarting
23:16:15 S4 cause: OOMKilled (exit 137): limit 48Mi, the repo says 128Mi
23:16:17 S4 fixed: manifest from git re-applied (limit 128Mi), 0 restarts, thumbs answers
23:17:06 S8 symptom: catalog rollout stuck, the new pod does not start, old pods still serve
23:17:07 S8 cause: image m21lab-tl-api:1.0.1 was never built or pushed, only 1.0 exists
23:17:07 S8 fixed: rollout undo to 1.0, 2/2 ready, catalog answers
23:17:24 S9 symptom: /api/courses answers 503 fast
23:17:24 S9 cause: nightly-report holds idle connections; max_connections=20 is used up
23:17:24 S9 fixed: report job stopped, its connections closed, /api/courses 200
```

Write-up: **symptom** `/api/courses` answered 503 in about 20 ms, so the database refused quickly rather than timing out; **cause** the nightly report holds 17 idle connections of the 20 PostgreSQL allows, and the rest are reserved for superusers (the journal's "remaining connection slots are reserved" line, then `pg_stat_activity`); **fix** stop the report job, and its connections close; **verified** 1 client connection left and a 200 from the user side; **prevent** fix the job to use one connection and close it, PgBouncer in front of the database, a per-role `CONNECTION LIMIT` for batch jobs, and an alert at 80% of `max_connections`. The `score` table at the end shows 0 to 2 seconds per step only because every step was scripted.

Cleanup: `./reset.sh all` brought every check back to healthy, then `zsh troubleshooting-labs/lab.sh down` and `zsh troubleshooting-labs/lab.sh check` printed nothing (only `docker ps`'s header line).

</details>

---

## Task 9 · Secret scanning, image signing and an admission policy
**Time box: 3 hours · Difficulty: Hard · Course: [M18-L01 - Shift Left](../security/m18-l01-shift-left/), [M18-L02 - Secrets Management](../security/m18-l02-secrets-management/), [M18-L03 - Supply-Chain Security](../security/m18-l03-supply-chain-security/), [M18-L04 - Kubernetes Security](../security/m18-l04-kubernetes-security/), [M18-B01 - A Secure Delivery Pipeline](../security/m18-b01-a-secure-delivery-pipeline/)**

### The brief

> **From the allcsvideos security team.** Three things, one goal: only reviewed, signed code runs in production. (1) Our deploy repository leaked an AWS key in an old commit: find it, clean the history, and stop the next leak at commit time. (2) Sign the `course-search` image (task 2) with cosign in a local registry, and write a deploy gate that resolves a tag to its digest, verifies the signature, and refuses anything unsigned. (3) Add an admission policy so that a namespace that opts in only accepts images from our registry, pinned by digest. Everything runs offline on a laptop.

### Starter files

**`make-repo.sh`** builds the deploy repository with a fixed history, so the commit hashes are the same for everyone. It's in [`m21-take-home/t09/starter/`](m21-take-home/t09/starter/make-repo.sh). The reference run, from the task folder (here `m21-take-home/t09/starter`): `docker run --rm --name m21lab-t09-git -v "$PWD":/t09 -e HOME=/tmp --entrypoint sh alpine/git:v2.49.1 -c 'rm -rf /t09/repo; sh /t09/make-repo.sh 2>&1; cp -R /repo /t09/repo'`, which printed `b38427c deploy: remove keys`, `09f9d39 deploy: keys for the upload job (quick fix)` and `24bee88 deploy: first config`:

```sh
#!/bin/sh
# make-repo.sh: builds the starter repository for task 9 (history fixed, so hashes are the same for everyone).
# Commit 2 contains a FAKE AWS key (lab only, never real), removed again in commit 3: it is still in the history.
set -eu
git init -q -b main /repo && cd /repo
git config user.name Priya && git config user.email priya@example.com
export GIT_AUTHOR_DATE="2026-10-01T10:00:00+05:30" GIT_COMMITTER_DATE="2026-10-01T10:00:00+05:30"
printf '# course-search deploy config\n' > README.md
printf 'REGION=ap-south-1\nBUCKET=allcs-videos\n' > deploy.env
git add -A && git commit -qm "deploy: first config"
export GIT_AUTHOR_DATE="2026-10-02T11:00:00+05:30" GIT_COMMITTER_DATE="2026-10-02T11:00:00+05:30"
printf 'AWS_ACCESS_KEY_ID=AKIA2FAKEDEMOKEYZZZZ\nAWS_SECRET_ACCESS_KEY=fakeDEMOsecretKEY0000000000000000000000FAKE\n' >> deploy.env
git add -A && git commit -qm "deploy: keys for the upload job (quick fix)"
export GIT_AUTHOR_DATE="2026-10-03T09:30:00+05:30" GIT_COMMITTER_DATE="2026-10-03T09:30:00+05:30"
printf 'REGION=ap-south-1\nBUCKET=allcs-videos\n' > deploy.env
git add -A && git commit -qm "deploy: remove keys"
git log --oneline
```

**A lab registry**, published on your laptop only. The reference run: `docker run -d --name m21lab-t09-registry --label course=devops -p 127.0.0.1:21055:5000 --memory 128m registry:3.1.2`, then `docker tag m21lab-t02-app:1.0.0 localhost:21055/allcs/course-search:1.0.0` and `docker push -q localhost:21055/allcs/course-search:1.0.0` (Docker Desktop allows plain HTTP to `localhost` registries).

**A cluster** for the policy: the kind cluster and tool box from task 6 (Kubernetes v1.37).

### Acceptance criteria
1. A gitleaks scan of the history finds the key, and after your cleanup the same scan finds nothing. The real key would be revoked first: say so in the README, in that order.
2. A pre-commit hook that blocks a commit whose staged changes contain a secret, shown blocking one.
3. A cosign key pair (password from an environment variable, never in a file), the image signed **by digest**, and `cosign verify` passing.
4. A deploy gate script that resolves a tag to a digest, verifies it, and prints the pinned reference to deploy, or exits non-zero. Shown refusing an unsigned image pushed over the same tag, and accepting the signed one.
5. A ValidatingAdmissionPolicy and binding: in namespaces labelled `allcs.io/enforce-images=true`, Pods, Deployments, StatefulSets and DaemonSets are denied unless every container and init container image starts with `registry.lab:5000/allcs/` and contains `@sha256:`. Shown with server-side dry runs: a tag denied, another registry denied, a digest admitted, and an unlabelled namespace unaffected.
6. A README section on what this does **not** protect against.

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 20 | Leak response in the right order, and a history that's really clean |
| 20 | Signing by digest, verification in the deploy path, and the tamper test |
| 25 | The admission policy: correct CEL, all workload kinds, init containers, an opt-in binding, clear messages |
| 15 | Defence in depth: what each layer covers and what's left |
| 20 | Scripts that are safe to run (quoting, exit codes) and a README a teammate can follow |

### Stretch goals
- Kyverno 1.19 (chart 3.9.2) on `kindest/node:v1.35.8`, with an ImageValidatingPolicy that verifies the cosign signature at admission (keep the native policy too, and compare).
- Attach an SBOM (Syft) as a signed attestation and verify it in the gate with `cosign verify-attestation`.
- Run the gitleaks scan and the gate as jobs in task 4's CI lab.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**Part 1, the leak.** The working tree is clean; the history isn't:

```text
$ gitleaks dir --redact --no-banner --no-color .
11:09PM INF scanned ~68 bytes (68 bytes) in 13.5ms
11:09PM INF no leaks found
exit 0
$ gitleaks git --redact --no-banner --no-color -v .
Finding:     REDACTED
Secret:      REDACTED
RuleID:      aws-access-token
Entropy:     3.208695
File:        deploy.env
Line:        3
Commit:      09f9d399c02eff0de1e2f88154e5d05979769dc7
Author:      Priya
Email:       priya@example.com
Date:        2026-10-02T05:30:00Z
Fingerprint: 09f9d399c02eff0de1e2f88154e5d05979769dc7:deploy.env:aws-access-token:3

11:09PM INF 3 commits scanned.
11:09PM INF scanned ~173 bytes (173 bytes) in 40ms
11:09PM WRN leaks found: 1
exit 1
```

gitleaks flags the access key but not the secret key, because its value contains "FAKE" and gitleaks's allow rules skip such values; a real secret key would be flagged too. So the cleanup replaces both. First, in real life, both keys are revoked and CloudTrail is checked; only then is the history rewritten. **`replacements.txt`** (mounted into the container as `/r.txt`):

```text
AKIA2FAKEDEMOKEYZZZZ==>REMOVED-ROTATED-KEY
fakeDEMOsecretKEY0000000000000000000000FAKE==>REMOVED-ROTATED-SECRET
```

```text
$ cat /r.txt
AKIA2FAKEDEMOKEYZZZZ==>REMOVED-ROTATED-KEY
fakeDEMOsecretKEY0000000000000000000000FAKE==>REMOVED-ROTATED-SECRET
$ git filter-repo --sensitive-data-removal --replace-text /r.txt --force

Parsed 3 commitsHEAD is now at 6be0e32 deploy: remove keys

New history written in 0.02 seconds; now repacking/cleaning...
You rewrote 2 (of 3) commits.

NOTE: First Changed Commit(s) is/are:
  09f9d399c02eff0de1e2f88154e5d05979769dc7
NOTE: LFS object orphaning not checked (LFS not in use)

Repacking your repo and cleaning out old unneeded objects
Completely finished after 0.09 seconds.

…
$ git log --oneline
6be0e32 deploy: remove keys
04729f6 deploy: keys for the upload job (quick fix)
24bee88 deploy: first config
$ git show HEAD~1:deploy.env
REGION=ap-south-1
BUCKET=allcs-videos
AWS_ACCESS_KEY_ID=REMOVED-ROTATED-KEY
AWS_SECRET_ACCESS_KEY=REMOVED-ROTATED-SECRET
$ gitleaks git --redact --no-banner --no-color -v .
11:11PM INF 3 commits scanned.
11:11PM INF scanned ~151 bytes (151 bytes) in 34.7ms
11:11PM INF no leaks found
exit 0
```

(`git filter-repo` 2.47.0 installed with pip in `python:3.13.16-slim`; the rewritten commits get new hashes, so everyone re-clones, and the forge must drop the old objects too, as [M18-L02](../security/m18-l02-secrets-management/) shows.)

**`hooks/pre-commit`**

```sh
#!/bin/sh
# .git/hooks/pre-commit: block a commit whose staged changes contain a secret.
# On a laptop with only Docker, swap the last line for:
#   docker run --rm -v "$PWD":/repo -w /repo zricethezav/gitleaks:v8.30.1 git --pre-commit --staged --redact --no-banner -v
exec gitleaks git --pre-commit --staged --redact --no-banner --no-color -v
```

Installed in a clone and tried with a fake database password (run inside the gitleaks image, which also contains git):

```text
$ printf "DB_PASSWORD=k8Hq2Zx7Vt4Lm9Pw3Rb6\n" >> deploy.env   # FAKE lab value
$ git commit -am "deploy: database password"
Finding:     DB_PASSWORD=REDACTED
Secret:      REDACTED
RuleID:      generic-api-key
Entropy:     4.321928
File:        deploy.env
Line:        3
Fingerprint: deploy.env:generic-api-key:3

11:09PM INF 0 commits scanned.
11:09PM INF scanned ~33 bytes (33 bytes) in 42ms
11:09PM WRN leaks found: 1
exit 1
$ git log --oneline -1
b38427c deploy: remove keys
```

The commit was refused, and `HEAD` didn't move.

**Part 2, signing.** cosign v3.1.4 in a container with `--network host`, `COSIGN_PASSWORD` set from the environment, offline flags for a lab registry without a transparency log ([M18-L03](../security/m18-l03-supply-chain-security/)):

```text
…
$ cosign generate-key-pair
Private key written to cosign.key
Public key written to cosign.pub
exit 0
$ cosign signing-config create --out lab-signing-config.json
exit 0
$ cosign sign --key cosign.key --signing-config lab-signing-config.json --allow-http-registry -y localhost:21055/allcs/course-search@sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e
Pushing signature to: localhost:21055/allcs/course-search
Signing artifact...
exit 0
$ cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry -o text localhost:21055/allcs/course-search@sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e
WARNING: Skipping tlog verification is an insecure practice that lacks transparency and auditability verification for the signature.
{"critical":{"identity":{"docker-reference":"localhost:21055/allcs/course-search@sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e"},"image":{"docker-manifest-digest":"sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e"},"type":"https://sigstore.dev/cosign/sign/v1"},"optional":{}}

Verification for localhost:21055/allcs/course-search@sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The signatures were verified against the specified public key
exit 0
```

The tamper test, someone pushing a different image over the same tag:

```text
# staged: someone pushes a different image over the same tag
$ docker tag m21lab-t02-app:starter localhost:21055/allcs/course-search:1.0.0 && docker push -q localhost:21055/allcs/course-search:1.0.0
localhost:21055/allcs/course-search:1.0.0
$ cosign verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry -o text localhost:21055/allcs/course-search:1.0.0
WARNING: Skipping tlog verification is an insecure practice that lacks transparency and auditability verification for the signature.
Error: no signatures found
error during command execution: no signatures found
exit 10
```

**`deploy-gate.sh`**

```bash
#!/usr/bin/env bash
# deploy-gate.sh REF: resolve REF to a digest, verify its signature, and print the pinned reference to deploy.
# Exits non-zero (and deploys nothing) when the digest has no valid signature from our key.
set -euo pipefail
ref=${1:?usage: deploy-gate.sh REGISTRY/REPO:TAG}
COSIGN=(docker run --rm --network host -v "$PWD/keys:/keys:ro" -w /keys ghcr.io/sigstore/cosign/cosign:v3.1.4)   # an array: paths may contain spaces
digest=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest.Digest}}' | tr -d '"')
pinned="${ref%:*}@$digest"
echo "resolved $ref -> $digest"
if "${COSIGN[@]}" verify --key cosign.pub --insecure-ignore-tlog --allow-http-registry "$pinned" >/dev/null 2>&1; then
  echo "signature OK: deploy ${pinned/localhost:21055/registry.lab:5000}"
else
  echo "REFUSED: $pinned has no valid signature from cosign.pub" >&2; exit 1
fi
```

Its first version stored the cosign command in a plain string, and refused even the signed image: the task folder's path contains spaces, so the unquoted `$COSIGN` split the `-v` mount in two. Storing the command in an array fixed it. The final run:

```text
# staged: the tag 1.0.0 was overwritten with an unsigned image
$ ./deploy-gate.sh localhost:21055/allcs/course-search:1.0.0
resolved localhost:21055/allcs/course-search:1.0.0 -> sha256:76849081325ba450cfb5404cf48ec4401e0519f78586676c5a8f3a02b9360ac0
REFUSED: localhost:21055/allcs/course-search@sha256:76849081325ba450cfb5404cf48ec4401e0519f78586676c5a8f3a02b9360ac0 has no valid signature from cosign.pub
exit 1
# the signed image pushed back to the tag
$ ./deploy-gate.sh localhost:21055/allcs/course-search:1.0.0
resolved localhost:21055/allcs/course-search:1.0.0 -> sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e
signature OK: deploy registry.lab:5000/allcs/course-search@sha256:e8c7f1c24969b9824611db0e4b8dd7e46cc0fea55ac77f391bdc4d0db64e323e
exit 0
```

**Part 3, the admission policy.** **`policy/image-policy.yaml`**

```yaml
# Only images from our registry, pinned by digest, in namespaces that opt in.
# Native ValidatingAdmissionPolicy (CEL, GA since Kubernetes 1.30): no extra controller to run.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: allcs-pinned-images
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
      - apiGroups: [apps]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [deployments, statefulsets, daemonsets]
  variables:
    - name: spec
      expression: "object.kind == 'Pod' ? object.spec : object.spec.template.spec"
    - name: images
      expression: >-
        variables.spec.containers.map(c, c.image) +
        (has(variables.spec.initContainers) ? variables.spec.initContainers.map(c, c.image) : [])
  validations:
    - expression: "variables.images.all(i, i.startsWith('registry.lab:5000/allcs/'))"
      messageExpression: "'images must come from registry.lab:5000/allcs/, got: ' + variables.images.join(', ')"
    - expression: "variables.images.all(i, i.contains('@sha256:'))"
      messageExpression: "'images must be pinned by digest (@sha256:...), got: ' + variables.images.join(', ')"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: allcs-pinned-images
spec:
  policyName: allcs-pinned-images
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels: {allcs.io/enforce-images: "true"}
```

The three test Deployments differ only in their image: `registry.lab:5000/allcs/course-search:1.0.0` (`tests/by-tag.yaml`), a Docker Hub image by digest (`tests/other-registry.yaml`), and `registry.lab:5000/allcs/course-search@sha256:e8c7f1c2…` (`tests/by-digest.yaml`). On the task 6 cluster (Kubernetes v1.37.0):

```text
$ kubectl apply -f policy/image-policy.yaml
validatingadmissionpolicy.admissionregistration.k8s.io/allcs-pinned-images created
validatingadmissionpolicybinding.admissionregistration.k8s.io/allcs-pinned-images created
exit 0
$ kubectl create namespace shop && kubectl label namespace shop allcs.io/enforce-images=true
namespace/shop created
namespace/shop labeled
exit 0
$ kubectl -n shop apply --dry-run=server -f tests/by-tag.yaml
The deployments "by-tag" is invalid: : ValidatingAdmissionPolicy 'allcs-pinned-images' with binding 'allcs-pinned-images' denied request: images must be pinned by digest (@sha256:...), got: registry.lab:5000/allcs/course-search:1.0.0
exit 1
$ kubectl -n shop apply --dry-run=server -f tests/other-registry.yaml
The deployments "other-registry" is invalid: : ValidatingAdmissionPolicy 'allcs-pinned-images' with binding 'allcs-pinned-images' denied request: images must come from registry.lab:5000/allcs/, got: docker.io/library/nginx@sha256:0000000000000000000000000000000000000000000000000000000000000000
exit 1
$ kubectl -n shop apply --dry-run=server -f tests/by-digest.yaml
deployment.apps/by-digest created (server dry run)
exit 0
$ kubectl -n default apply --dry-run=server -f tests/by-tag.yaml
deployment.apps/by-tag created (server dry run)
exit 0
```

**What this doesn't protect against (for the README):** the native policy checks where an image comes from and that it's pinned, not that it's signed: a digest pushed by an attacker with registry access would pass admission, which is why the deploy gate verifies the signature and why Kyverno or the Sigstore policy controller is the next step; `--insecure-ignore-tlog` is acceptable only in this offline lab; the binding is opt-in per namespace, so a new namespace is unprotected until labelled (a second policy can require the label); and the pre-commit hook can be skipped with `--no-verify`, so the same scan must be a required CI check.

</details>

---

## Task 10 · A design document: decision record, reference architecture and rollout plan
**Time box: 3 to 4 hours · Difficulty: Hard · Course: [M20-L01 - Designing a Production Delivery Platform](../capstones/m20-l01-designing-a-production-delivery-platform/), [M09-L02 - Deployment Strategies](../ci/m09-l02-deployment-strategies/), [M15-L03 - GitOps with Argo CD](../k8s/m15-l03-gitops-with-argo-cd/), [M17-L01 - SLIs, SLOs and Error Budgets](../observability/m17-l01-slis-slos-and-error-budgets/)**

### The brief

> **From the allcsvideos engineering managers.** The API runs on Kubernetes with a default rolling update, deployed by Argo CD from Git. Last quarter, two releases broke the course list for every student before anyone noticed, and each rollback was a manual `kubectl rollout undo` after a page. We want a release process where a bad release hurts few users, for a short time, without a person watching. Send us three documents: an architecture decision record (MADR 4.0.0) that compares at least three options and picks one; a one-page reference architecture of the release path; and a rollout and rollback plan for the first release with it. Our format checkers must pass. You'll present it in a 30-minute review, so we'll ask why.

(The two broken releases are this task's scenario, not a course measurement.)

### Starter files

**`check_adr.py`** (from [M20-L01](../capstones/m20-l01-designing-a-production-delivery-platform/): checks an ADR against the MADR 4.0.0 template)

```python
"""check_adr.py: checks ADR files against the MADR 4.0.0 template.
Required: front matter with status and date, a title, and the sections
Context and Problem Statement, Considered Options, Decision Outcome (in order)."""
import re, sys
REQ = ["Context and Problem Statement", "Considered Options", "Decision Outcome"]
STATUS = {"proposed", "rejected", "accepted", "deprecated", "superseded"}
bad = 0
for path in sys.argv[1:]:
    txt = open(path, encoding="utf-8").read()
    errs = []
    fm = re.match(r"^---\n(.*?)\n---\n", txt, re.S)
    meta = dict(l.split(": ", 1) for l in fm.group(1).splitlines()) if fm else {}
    if meta.get("status") not in STATUS: errs.append("status")
    if not re.fullmatch(r"\d{4}-\d\d-\d\d", meta.get("date", "")): errs.append("date")
    if not re.search(r"^# \S", txt, re.M): errs.append("title")
    heads = re.findall(r"^## (.+)$", txt, re.M)
    pos = [heads.index(h) if h in heads else -1 for h in REQ]
    errs += [h for h, p in zip(REQ, pos) if p < 0]
    if all(p >= 0 for p in pos) and pos != sorted(pos): errs.append("order")
    opts = len(re.findall(r"^\* ", txt.split("## Considered Options")[-1].split("\n## ")[0], re.M))
    if opts < 2: errs.append("options")
    name = path.split("/")[-1]
    if errs: bad += 1; print(f"FAIL {name}: missing {', '.join(errs)}")
    else: print(f"ok   {name}  {meta['status']}, {opts} options")
print(f"{len(sys.argv) - 1 - bad} of {len(sys.argv) - 1} ADRs follow MADR 4.0.0")
sys.exit(1 if bad else 0)
```

**`check_plan.py`** (checks a rollout plan has what a reviewer needs before approving a release)

```python
"""check_plan.py: checks a rollout plan has the sections a reviewer needs before approving a release.
Required headings (## level, in this order): Scope, Preconditions, Rollout steps, Go / no-go criteria,
Rollback, Communication. Rollout steps must be a numbered list, every go / no-go bullet must contain a
number, and the Rollback section must state a time target (minutes or seconds)."""
import re
import sys

REQ = ["Scope", "Preconditions", "Rollout steps", "Go / no-go criteria", "Rollback", "Communication"]
bad = 0
for path in sys.argv[1:]:
    txt = open(path, encoding="utf-8").read()
    errs = []
    heads = re.findall(r"^## (.+)$", txt, re.M)
    pos = [heads.index(h) if h in heads else -1 for h in REQ]
    errs += [f"section '{h}'" for h, p in zip(REQ, pos) if p < 0]
    if all(p >= 0 for p in pos) and pos != sorted(pos):
        errs.append("section order")
    body = {h: (txt.split(f"## {h}\n", 1) + [""])[1].split("\n## ")[0] for h in REQ}
    steps = re.findall(r"^\d+\. ", body["Rollout steps"], re.M)
    if len(steps) < 3:
        errs.append("at least 3 numbered rollout steps")
    crit = [l for l in body["Go / no-go criteria"].splitlines() if l.startswith(("* ", "- "))]
    if not crit or any(not re.search(r"\d", l) for l in crit):
        errs.append("a number in every go / no-go line")
    if not re.search(r"\d+\s*(minutes?|min|seconds?|s)\b", body["Rollback"]):
        errs.append("a rollback time target")
    name = path.split("/")[-1]
    if errs:
        bad += 1
        print(f"FAIL {name}: needs {', '.join(errs)}")
    else:
        print(f"ok   {name}  {len(steps)} steps, {len(crit)} go / no-go lines")
print(f"{len(sys.argv) - 1 - bad} of {len(sys.argv) - 1} plans are ready for review")
sys.exit(1 if bad else 0)
```

Run them in a container: `docker run --rm --network none -v "$PWD":/w:ro -w /w python:3.13.16-slim python check_adr.py adr/*.md`, and the same for `check_plan.py`.

### Acceptance criteria
1. `check_adr.py` and `check_plan.py` exit 0 on your documents.
2. The ADR has decision drivers, at least three considered options with pros and cons, a chosen option with its reason, consequences (good and bad), and a **Confirmation** section that says how you'll know the decision was right.
3. The reference architecture fits on one page: requirements with numbers, the path from commit to users, owners per component, and the trade-offs you accept.
4. The rollout plan has numbered steps, go and no-go criteria with numbers taken from the SLO, rollback paths each with a time target, and who is told what, when.
5. Nothing in the documents contradicts the facts of the course (the SLO, the tools in use, what a rollback does and doesn't undo).

### How it will be evaluated

| Points | What the reviewer checks |
|---|---|
| 25 | The decision: options that are real alternatives, honest cons, a reason tied to the drivers |
| 20 | Gates from the SLO: the right signals, numbers, and what happens at low traffic |
| 20 | Rollback: every path covered (during, after, the tooling itself), with time targets |
| 15 | Risks and trade-offs named, including what the choice costs to run |
| 10 | Communication and ownership |
| 10 | Clarity: short, scannable, no filler; the checkers pass |

### Stretch goals
- A staging drill plan that proves the Confirmation section, with the numbers you'd record.
- A second ADR for the traffic router (replica-based weights versus the Gateway API versus a service mesh).
- A one-slide summary for the review, and a list of the five questions you expect.

<details>
<summary><b>Reference solution (spoilers)</b></summary>

**`adr/0007-api-canary-releases.md`**

```markdown
---
status: proposed
date: 2026-10-22
decision-makers: Asha, Rahul
consulted: Priya
informed: Meera, support
---

# Release the API with automated canaries, gated on the SLO

## Context and Problem Statement

The API runs on Kubernetes as a Deployment with a default rolling update.
In the last quarter two releases broke the course list for every student
before anyone noticed, and each rollback was a manual `kubectl rollout undo`
after a page. How should a new API version reach users so that a bad
release hurts few users, for a short time, without a person watching?

## Decision Drivers

* Limit the blast radius: a bad release should reach at most a small share of requests.
* Decide from the user's view: the SLI the SLO uses (5xx ratio and p99 latency), not CPU.
* Roll back automatically, in minutes, without cluster credentials in CI.
* Fit what the team already runs: GitOps with Argo CD, Prometheus, one cluster per environment.
* Database changes must stay backward compatible (expand, migrate, contract), whatever the strategy.

## Considered Options

* Keep the rolling update, add readiness probes and a manual post-deploy check
* Blue-green: a full second Deployment and a Service switch
* Canary with Argo Rollouts and Prometheus analysis

## Decision Outcome

Chosen option: "Canary with Argo Rollouts and Prometheus analysis", because it
is the only option that sends a small, growing share of real traffic to the new
version and stops on its own when the SLI degrades, and it plugs into Argo CD,
which already applies every change from Git.

### Consequences

* Good, because a bad release reaches 10% of requests for a few minutes, then rolls back by itself.
* Good, because the gate uses the same SLI as the SLO and its burn-rate alerts.
* Bad, because the team must run and upgrade one more controller (Argo Rollouts).
* Bad, because low-traffic hours give the analysis few requests: the gate needs a minimum request count.
* Neutral, because old and new versions serve at the same time, so APIs and schemas must stay compatible (already a rule).

### Confirmation

Before this ADR is accepted, a staging drill must show: a release with an injected
10% error rate is aborted by the analysis and fully rolled back within 5 minutes,
with at most 10% of staging requests exposed; and a healthy release reaches 100%
with no manual step. Results go into the rollout plan's review.

## Pros and Cons of the Options

### Keep the rolling update, add readiness probes and a manual post-deploy check

* Good, because nothing new to run; readiness probes alone stopped failed requests during rollouts in the course lab (M13-L04).
* Bad, because every new pod gets real traffic as soon as it is ready: a bad version reaches all users within one rollout.
* Bad, because the check and the rollback depend on a person.

### Blue-green: a full second Deployment and a Service switch

* Good, because the switch and the switch back are one change each.
* Good, because the new version can be tested with production config before any user sees it.
* Bad, because it needs twice the capacity during a release.
* Bad, because after the switch 100% of users are on the new version at once.

### Canary with Argo Rollouts and Prometheus analysis

* Good, because exposure grows in steps (10%, 25%, 50%, 100%) with an analysis between steps.
* Good, because aborting returns all traffic to the stable ReplicaSet.
* Bad, because traffic-share precision depends on replica counts unless a traffic router (Gateway API or a mesh) is added.

## More Information

Related: the SLO and burn-rate alerts (M17-L01), deployment strategies (M09-L02),
GitOps (M15-L03). Revisit if traffic grows enough to justify header-based routing
for staff-first canaries.
```

**`reference-architecture.md`**

````markdown
# API release path: reference architecture

Version 1, 2026-10-22. Owner: Asha. Decision record: ADR 0007.

## Requirements

| Driver | Value |
|---|---|
| SLO | course list: 99.9% of requests succeed over 30 days; p99 under 250 ms |
| Blast radius | a bad release reaches at most 10% of requests |
| Detection | the release decides by itself within 5 minutes of exposure |
| Rollback | automatic, all traffic back on the stable version within 5 minutes |
| Team | 3 product teams ship; 2 platform engineers own the path |

## The path, from commit to users

```text
  Priya's pull request
        |  CI: lint, test, scan, build once, sign, push by digest
        v
  registry: api@sha256:...  ------------------------------+
        |                                                 |
  pull request to the GitOps repo: image digest bump      |
        |  reviewed, merged                               |
        v                                                 |
  Argo CD (in the cluster) syncs the Rollout object       |
        |                                                 |
        v                                                 |
  Argo Rollouts controller                                |
        |  step 1: 10% of pods new  -> analysis (5 min)   |
        |  step 2: 25%              -> analysis (5 min)   |
        |  step 3: 50%              -> analysis (5 min)   |
        |  step 4: 100%, old ReplicaSet scaled down       |
        |                                                 |
        |  analysis = Prometheus queries on the canary:   |
        |   5xx ratio, p99 latency, request count         |
        |  fail -> abort -> 100% back to stable  <--------+
        v
  students (Lukas in Frankfurt) through the Gateway and the Service
```

## Components and owners

| Component | Runs where | Owner | Notes |
|---|---|---|---|
| CI pipeline | GitHub Actions | platform | builds once; promotes the same digest |
| GitOps repo | Git | each product team | one folder per environment, reviewed PRs |
| Argo CD | each cluster | platform | pulls; CI holds no cluster credentials |
| Argo Rollouts | each cluster | platform | replaces the API Deployment with a Rollout |
| Prometheus | each cluster | platform | canary pods labelled `rollouts-pod-template-hash`, so queries split stable from canary |
| Burn-rate alerts | Alertmanager | on-call | still page if a release slips through the gate |

## Trade-offs we accept

* Replica-based weights: with 4 replicas, 10% is really "1 of 4 pods" (25%). Until a traffic router is added, run at least 10 replicas during a release, or accept the coarser step.
* The analysis needs traffic: below 50 requests in a step window the result is "inconclusive" and the rollout pauses for a person.
* Database migrations run before the rollout and must be backward compatible; the canary never rolls back a schema.
````

**`rollout-plan.md`**

```markdown
# Rollout plan: the first API release with canaries (API 2.6.0)

Owner: Asha (release lead). Approver: Rahul. Date: the first Tuesday after ADR 0007 is accepted, 10:00 IST.

## Scope

Replace the API Deployment with an Argo Rollouts Rollout in staging, then production,
and ship API 2.6.0 through it. Out of scope: the storefront, Course Copilot, the database.

## Preconditions

* ADR 0007 accepted after the staging drill in its Confirmation section passed.
* Argo Rollouts installed by Argo CD in both clusters, version pinned in the GitOps repo.
* AnalysisTemplate `api-slo` merged and dry-run against last week's metrics: it would have passed every good release.
* API 2.6.0 has no schema change (checked in its pull request).
* The on-call engineer knows the release window, and the status page has a draft message ready.

## Rollout steps

1. Staging: merge the pull request that converts the Deployment to a Rollout with the same pod template (no version change). Verify that Argo CD shows Synced and Healthy and the pod count is unchanged.
2. Staging: ship 2.6.0. Watch every step's analysis run pass. Record the time each step took.
3. Staging: ship a build of 2.6.0 with an injected 10% error rate (lab flag). Confirm the analysis aborts at step 1 and all pods are back on stable.
4. Production: merge the Deployment-to-Rollout conversion at 10:00 IST, outside the evening peak. Verify Synced and Healthy.
5. Production: merge the 2.6.0 digest bump. Watch steps 10%, 25%, 50% and their analysis runs; the release lead posts each result in the release channel.
6. Production: after 100%, watch the burn-rate panels for 30 minutes before closing the release. (With replica-based canaries the old ReplicaSet is scaled down as the canary grows, so a rollback after 100% is a new rollout of the previous digest.)
7. Write the release review: times per step, any inconclusive analysis, and whether the thresholds need tuning.

## Go / no-go criteria

* Canary 5xx ratio under 0.5% over each 5-minute step (more than 0.5% aborts).
* Canary p99 latency under 250 ms over each step (250 ms or more aborts).
* At least 50 canary requests per step, or the step pauses for a person.
* No page from the burn-rate alerts (14.4x over 1 hour, 6x over 6 hours) during the release.
* Error budget remaining above 25% before starting; below 25%, only fixes ship.

## Rollback

* Automatic: a failed analysis aborts the Rollout and moves 100% back to the stable ReplicaSet. Target: all traffic on stable within 5 minutes of the failed measurement.
* Manual, during the release: `kubectl argo rollouts abort api -n allcs`, then revert the digest bump in the GitOps repo so Git matches the cluster. Target: 5 minutes.
* After 100%: revert the digest bump in the GitOps repo; the previous image is still cached on the nodes. In an emergency, skip the remaining canary steps with `kubectl argo rollouts promote --full api -n allcs`. Target: 10 minutes.
* If the Rollout controller itself misbehaves: revert the conversion pull request; Argo CD restores the plain Deployment. Target: 15 minutes.

## Communication

* Before: a note in the release channel the day before, and to support (Meera's team) with the window.
* During: the release lead posts each step's result; the on-call engineer is told before production step 5.
* On abort: the release lead posts within 5 minutes; a status page update only if users were affected for more than 5 minutes.
* After: the release review in the next platform sync, and the thresholds updated by pull request if needed.
```

**Verification**, with two staged drafts next to the final documents, to show what the checkers catch (`drafts/0007-draft.md` has no front matter and a single option; `drafts/rollout-draft.md` has two steps, no numbers and no rollback target):

```text
$ python check_adr.py adr/0007-api-canary-releases.md drafts/0007-draft.md
ok   0007-api-canary-releases.md  proposed, 3 options
FAIL 0007-draft.md: missing status, date, Considered Options, options
1 of 2 ADRs follow MADR 4.0.0
exit 1
$ python check_plan.py rollout-plan.md drafts/rollout-draft.md
ok   rollout-plan.md  7 steps, 5 go / no-go lines
FAIL rollout-draft.md: needs section 'Preconditions', section 'Communication', at least 3 numbered rollout steps, a number in every go / no-go line, a rollback time target
1 of 2 plans are ready for review
exit 1
$ python check_adr.py adr/0007-api-canary-releases.md
ok   0007-api-canary-releases.md  proposed, 3 options
1 of 1 ADRs follow MADR 4.0.0
exit 0
$ python check_plan.py rollout-plan.md
ok   rollout-plan.md  7 steps, 5 go / no-go lines
1 of 1 plans are ready for review
exit 0
```

The checkers only prove the shape. The review is about the content, so be ready for questions like these: why not blue-green, if rollback is faster? What does 10% mean with 4 replicas? What happens at 3 a.m. with 20 requests per step? Who can skip the analysis, and how is that recorded? What did this cost to run, and who upgrades Argo Rollouts?

</details>

---

## After the tasks

**Clean up** each task as you finish it. For the reference runs, every one of these printed nothing at the end:

```bash
docker ps -a --filter name=m21lab
docker network ls --filter name=m21lab -q
docker volume ls --filter name=m21lab -q
docker images --filter reference='m21lab*' -q
```

Delete the kind clusters you created with `kind delete cluster --name <name>`, and leave the shared `kind` network alone. Pulled base images can stay.

**Score yourself.** Use each task's rubric honestly: 70 points or more on a task means you'd likely pass that round; under 50, redo it after rewatching the lessons named under its title. Then pick your **three best** tasks, put them in a public repository each, with a README that shows how to run it with Docker only, the test that proves the hardest criterion, and the trade-offs you made. That's what an interviewer opens first, and what you'll talk through in the review. The talking half is in **[Module 21 final practice sheet](m21-final.md)**: 75 questions, several of which (8, 26, 43, 51, 52, 59, 63, 68) come straight from these tasks' real outputs.

