# M03-L04 · Python for Ops
> Video: Module 3, Lesson 4. Watch it first, then follow along here.

## What you'll learn
- When a script has outgrown Bash: structured data, data structures, error handling, tests, size
- Running programs safely with `subprocess.run` and a list: return codes, `check=True`, timeouts
- Reading files and disks with `pathlib`, `collections.Counter` and `shutil.disk_usage`
- Honest HTTP checks with `urllib.request`, a timeout and the right `except` blocks
- A small command-line tool (`healthcheck.py`): argparse, logging on stderr, `--json`, a thread pool and an honest exit code
- Installing a third-party library (`requests`) the right way, in a virtual environment

## Before you start
- Docker Desktop (or Docker Engine on Linux) and a terminal with bash. On Windows, use WSL2 or Git Bash.
- Images used, exactly as in the video: `ubuntu:24.04` (Python 3.12.3 and pip 24.0 from Ubuntu's packages) and `python:3.13.16-slim` for the two stand-in services.
- `up.sh` installs packages with `apt` inside web-01, so you need an internet connection.
- It helps to have done [M03-L03](../m03-l03-scheduling-and-automation). If its lab is still running, remove it first (`../m03-l03-scheduling-and-automation/lab/down.sh`): both labs use the name `web-01`.

## Files in this folder
| File | What it is |
|---|---|
| `scripts/api-check.sh` | Asha's Bash API check that greps JSON (the false all-clear in the hook) |
| `scripts/logstats.py` | nginx log sizes, status codes, 5xx by path, and disk usage |
| `scripts/httpcheck.py` | One HTTP request with a timeout, reporting every kind of failure honestly |
| `scripts/healthcheck.py` | The command-line tool: disks, services and HTTP endpoints, text or `--json` |
| `scripts/endpoints.json` | The URLs `healthcheck.py` checks (storefront, api, courses, copilot) |
| `scripts/req.py` | The API check again, with the `requests` library |
| `scripts/backup.py`, `scripts/backup.v2.py` | Pitfall: an unchecked return code, then fixed with `check=True` |
| `scripts/quiet.py`, `scripts/quiet.v2.py` | Pitfall: `except Exception: pass`, then fixed by catching by name and exiting 1 |
| `lab/up.sh`, `lab/down.sh` | Start and remove the lab: `web-01`, `api-01`, `copilot-01` on the network `lab-net` |
| `lab/setup-root.sh` | Prepares web-01 (user asha, nginx, the sample access log, the scripts in asha's home). Run by `up.sh` |
| `lab/services/standin.py` | STAND-INS for the API (port 8080) and Course Copilot (port 8000), with staging switches |
| `lab/gen_logs.py` | Generates the nginx sample log from M02-L04 (generated data, not real traffic) |

The stand-ins have three staging switches, used below:
`/tmp/redis-down` in api-01 makes `/health` report Redis down; `/tmp/model-missing` in copilot-01 makes `/health` answer 503; `GET /slow` on either waits 60 seconds.

## Follow along

### Start the lab

1. On your laptop, start the lab, then log in to web-01 as asha. `up.sh` copies this folder into web-01 as `/lesson` and puts the first scripts in asha's home.
   ```bash
   ./lab/up.sh
   docker exec -it web-01 su - asha
   ```
   Keep a **second terminal on your laptop** open for the staging commands (marked "laptop" below). Everything else runs inside web-01.

### The hook: grep reads JSON wrong

2. Laptop: stage the Redis outage.
   ```bash
   docker exec api-01 touch /tmp/redis-down
   ```
   In web-01:
   ```bash
   ./api-check.sh
   echo $?
   curl -s http://api-01:8080/health
   curl -s http://api-01:8080/health | python3 -m json.tool --indent 2
   ```
   ```
   OK    api is healthy
   0
   {"status": "degraded", "checks": {"db": {"status": "ok"}, "redis": {"status": "down"}}}
   ```
   The grep found `"status": "ok"` inside the nested db check. A false all-clear.

### Python on the server

3. Check the version, then try the same check in the interactive prompt.
   ```bash
   python3 --version
   which python3
   python3
   ```
   At the `>>>` prompt:
   ```python
   import json, urllib.request
   resp = urllib.request.urlopen("http://api-01:8080/health", timeout=3)
   data = json.load(resp)
   data["status"]
   data["checks"]["redis"]["status"]
   [name for name, c in data["checks"].items() if c["status"] != "ok"]
   exit()
   ```
   You should see `'degraded'`, `'down'` and `['redis']`.

4. Laptop: bring Redis back.
   ```bash
   docker exec api-01 rm /tmp/redis-down
   ```

### Running commands: subprocess

5. Start `python3` again and run commands as lists.
   ```python
   import subprocess
   r = subprocess.run(["pgrep", "-x", "nginx"], capture_output=True, text=True)
   r.returncode
   r.stdout.split()
   subprocess.run(["pgrep", "-x", "apache2"]).returncode
   subprocess.run(["wc", "-l", "reports/error report.txt"])
   subprocess.run(["ls", "/nope"], check=True)
   subprocess.run(["sleep", "10"], timeout=2)
   exit()
   ```
   - nginx: return code `0` and a list of process IDs (the master and its workers). apache2: `1`, no exception.
   - The file name with a space arrives as one argument: `5 reports/error report.txt`.
   - `check=True` raises `CalledProcessError: Command '['ls', '/nope']' returned non-zero exit status 2.`
   - `timeout=2` raises `TimeoutExpired: Command '['sleep', '10']' timed out after ... seconds`.

### Files and disks

6. Read `logstats.py` (`cat logstats.py`), then run it.
   ```bash
   ./logstats.py
   ```
   ```
   access.log  1,196,345 bytes
   error.log           0 bytes
   status codes: {'200': 4452, '401': 954, '304': 308, '302': 132, '500': 73, '404': 14}
   5xx by path:  [('/api/checkout', 72), ('/api/progress', 1)]
   disk: 2.2% used, 844 GiB free
   ```
   The log numbers match the video (same generated sample). The disk line shows your own Docker disk.

### HTTP checks

7. Run `httpcheck.py` against a working page, a missing page, a closed port, an unknown host, and a page that hangs.
   ```bash
   ./httpcheck.py http://localhost/
   ./httpcheck.py http://api-01:8080/health
   ./httpcheck.py http://api-01:8080/nope
   ./httpcheck.py http://localhost:9999/
   ./httpcheck.py http://api-02:8080/
   ./httpcheck.py http://api-01:8080/slow
   ```
   ```
   HTTP 200 after 0.01 s
   HTTP 200 after 0.33 s
   HTTP 404 Not Found after 0.01 s
   unreachable: [Errno 111] Connection refused after 0.01 s
   unreachable: [Errno -2] Name or service not known after 0.02 s
   timed out after 3.02 s
   ```

### The tool: healthcheck.py

8. Help and bad input.
   ```bash
   ./healthcheck.py --help
   ./healthcheck.py --limit 200
   echo $?
   ./healthcheck.py --tmeout 5
   echo $?
   ```
   argparse writes the help for you. Both bad inputs print the usage line and an error, with exit code `2`.

9. A normal run, the thread pool measured, and verbose mode.
   ```bash
   ./healthcheck.py
   echo $?
   ./healthcheck.py --workers 1 > /dev/null
   ./healthcheck.py > /dev/null
   ./healthcheck.py -v --mount /data
   ```
   ```
   OK    disk /          2.2% used
   OK    disk /data      14.1% used
   OK    service nginx   running
   OK    storefront      HTTP 200 in 72 ms
   OK    api             HTTP 200 in 386 ms
   OK    courses         HTTP 200 in 679 ms
   OK    copilot         HTTP 200 in 983 ms
   2026-10-20 11:33:34 INFO finished in 0.99 s: all checks passed
   0
   ```
   With one worker it takes about 1.84 s; with four, about 0.97 s (the slowest check, not the sum). `-v` adds DEBUG lines on stderr for each step.

10. Break things on purpose. Laptop:
    ```bash
    docker exec copilot-01 touch /tmp/model-missing
    ```
    In web-01:
    ```bash
    sudo nginx -s stop
    ./healthcheck.py || echo "exit code $?"
    ./healthcheck.py --json
    ```
    ```
    WARN  service nginx   not running
    WARN  storefront      unreachable: [Errno 111] Connection refused
    WARN  copilot         HTTP 503 in 974 ms
    2026-10-20 11:33:50 WARNING finished in 0.98 s: 3 check(s) need a look
    exit code 1
    ```
    `--json` prints the same results as data: `"ok": false` at the top, and an `ok` and `detail` for each check.

11. Fix them. Laptop:
    ```bash
    docker exec copilot-01 rm /tmp/model-missing
    ```
    In web-01:
    ```bash
    sudo nginx
    ./healthcheck.py; echo $?
    ```
    All green again, exit code `0`.

### Third-party libraries: requests in a venv

12. Try a system-wide install, then do it the right way.
    ```bash
    pip install requests
    python3 -m venv ~/venv
    ~/venv/bin/pip install -q requests
    ~/venv/bin/pip list
    ~/venv/bin/python req.py
    ```
    The first command fails with `error: externally-managed-environment` (PEP 668). In the venv it works; the video got `requests 2.34.2` (20 Oct 2026). To match exactly, install `requests==2.34.2`. `req.py` prints `200 ok`.

### The pitfalls, live

13. `shell=True` with outside input. In `python3`:
    ```python
    import subprocess
    name = "access.log; echo injected, running as $(whoami)"
    subprocess.run(f"wc -l /var/log/nginx/{name}", shell=True)
    subprocess.run(["wc", "-l", f"/var/log/nginx/{name}"])
    exit()
    ```
    With `shell=True` the injected `echo` runs (`injected, running as asha`). As a list, it is just a strange file name: `No such file or directory`.

14. No timeout. This one hangs; press Ctrl+C after a few seconds:
    ```bash
    time python3 -c 'import urllib.request as u; u.urlopen("http://api-01:8080/slow")'
    ```
    You get a `KeyboardInterrupt` deep inside the socket code. Under cron, nobody presses Ctrl+C.

15. Not checking the return code.
    ```bash
    install -m 755 /lesson/scripts/backup.py ~/backup.py
    ./backup.py; echo $?
    install -m 755 /lesson/scripts/backup.v2.py ~/backup.py
    ./backup.py; echo $?
    ```
    First: `cp: cannot create regular file '/backup/': Not a directory`, then `backup done` and `0`. With `check=True`: a `CalledProcessError` traceback and `1`.

16. Catching everything, silently. Laptop:
    ```bash
    docker exec copilot-01 touch /tmp/model-missing
    ```
    In web-01:
    ```bash
    install -m 755 /lesson/scripts/quiet.py ~/quiet.py
    ./quiet.py; echo $?
    install -m 755 /lesson/scripts/quiet.v2.py ~/quiet.py
    ./quiet.py; echo $?
    ```
    ```
    copilot: 0 problem(s)
    0
    copilot: HTTP Error 503: Service Unavailable
    copilot: 1 problem(s)
    1
    ```
    Laptop, afterwards: `docker exec copilot-01 rm /tmp/model-missing`

17. Python 2 era advice.
    ```bash
    python --version
    python3 -c 'print "hello"'
    python3 -c 'import urllib2'
    ```
    `python: command not found`, a `SyntaxError` for `print` without brackets, and `No module named 'urllib2'` (today it is `urllib.request`).

## Common mistakes
- **`shell=True` with outside input.** A `;` or `$( )` in the data becomes code. Pass a list; if you truly need a shell, quote input with `shlex.quote`.
- **No timeout.** A check that can hang will hang one day, and under cron the next runs pile up. Give every command and every request a timeout.
- **Not checking the return code.** `subprocess.run` does not raise on a non-zero exit. Check `returncode`, or use `check=True`.
- **Catching everything silently.** `except Exception: pass` swallows real failures (and typos). Catch the exceptions you expect, by name, report them, and exit non-zero.
- **Python 2 era advice.** On Ubuntu 24.04 the command is `python3`, `print` needs brackets, and `urllib2` is gone. Python 2 reached end of life in 2020.
- **Parsing JSON with grep.** It can match the wrong field, as the hook showed. Use `json.load`.
- **`pip install` into the system Python.** Ubuntu blocks it (PEP 668). Use a virtual environment.

## Clean up
Leave web-01 with `exit`, then on your laptop:
```bash
./lab/down.sh
```
This removes the `web-01`, `api-01` and `copilot-01` containers and the `lab-net` network. The `ubuntu:24.04` and `python:3.13.16-slim` images stay; remove them with `docker image rm` if you do not need them for other lessons.

## Next
[M03-B01 · Build a Server Health-Check Toolkit](../m03-b01-build-a-server-health-check-toolkit)
