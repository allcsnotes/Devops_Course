#!/usr/bin/env python3
"""healthcheck.py: disks, services and HTTP endpoints on web-01."""
import argparse
import json
import logging
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

log = logging.getLogger("healthcheck")
ENDPOINTS = Path(__file__).with_name("endpoints.json")


def result(name, ok, detail):
    return {"check": name, "ok": ok, "detail": detail}


def check_disk(mount, limit):
    usage = shutil.disk_usage(mount)
    used = usage.used / usage.total * 100
    log.debug("disk %s: %.1f%% used, limit %d%%", mount, used, limit)
    return result(f"disk {mount}", used < limit, f"{used:.1f}% used")


def check_service(name):
    proc = subprocess.run(["pgrep", "-x", name],
                          capture_output=True, text=True)
    log.debug("pgrep -x %s: exit code %d", name, proc.returncode)
    if proc.returncode == 0:
        return result(f"service {name}", True, "running")
    if proc.returncode == 1:
        return result(f"service {name}", False, "not running")
    return result(f"service {name}", False, proc.stderr.strip())


def check_http(ep, timeout):
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(ep["url"], timeout=timeout) as resp:
            status, body = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        status, body = e.code, b""
    except urllib.error.URLError as e:
        return result(ep["name"], False, f"unreachable: {e.reason}")
    except TimeoutError:
        return result(ep["name"], False, f"no answer in {timeout:g} s")
    ms = (time.perf_counter() - start) * 1000
    log.debug("%s: HTTP %d in %.0f ms", ep["url"], status, ms)
    detail = f"HTTP {status} in {ms:.0f} ms"
    if status != 200:
        return result(ep["name"], False, detail)
    if "expect" in ep:
        try:
            state = json.loads(body).get("status")
        except ValueError:
            state = "not JSON"
        if state != ep["expect"]:
            return result(ep["name"], False, f"{detail}, status {state}")
    return result(ep["name"], True, detail)


def show(results):
    color = sys.stdout.isatty()
    for r in results:
        label = "OK  " if r["ok"] else "WARN"
        if color:
            label = f"\033[{32 if r['ok'] else 33}m{label}\033[0m"
        print(f"{label}  {r['check']:<15} {r['detail']}")


def parse_args():
    p = argparse.ArgumentParser(
        description="Check disks, services and HTTP endpoints.",
        epilog="exit codes: 0 all OK, 1 something needs a look, "
               "2 usage or config error")
    p.add_argument("--mount", action="append", metavar="PATH",
                   help="disk to check, repeatable (default: / and /data)")
    p.add_argument("--limit", type=int, default=80, metavar="PCT",
                   help="warn when a disk is this full (default: 80)")
    p.add_argument("--service", action="append", metavar="NAME",
                   help="process to look for, repeatable (default: nginx)")
    p.add_argument("--timeout", type=float, default=3, metavar="SEC",
                   help="seconds to wait for each URL (default: 3)")
    p.add_argument("--workers", type=int, default=4, metavar="N",
                   help="URLs to check at the same time (default: 4)")
    p.add_argument("--json", action="store_true",
                   help="print JSON for machines instead of text")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="log each step to stderr")
    args = p.parse_args()
    if not 1 <= args.limit <= 100:
        p.error(f"--limit must be from 1 to 100, got {args.limit}")
    return args


def main():
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%F %T")
    try:
        endpoints = json.loads(ENDPOINTS.read_text())
    except (OSError, ValueError) as e:
        log.error("cannot read %s: %s", ENDPOINTS, e)
        return 2

    start = time.perf_counter()
    results = [check_disk(m, args.limit) for m in args.mount or ["/", "/data"]]
    results += [check_service(s) for s in args.service or ["nginx"]]
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results += pool.map(lambda ep: check_http(ep, args.timeout), endpoints)

    failed = [r for r in results if not r["ok"]]
    if args.json:
        print(json.dumps({"host": socket.gethostname(), "ok": not failed,
                          "checks": results}, indent=2))
    else:
        show(results)
    took = time.perf_counter() - start
    if failed:
        log.warning("finished in %.2f s: %d check(s) need a look",
                    took, len(failed))
        return 1
    log.info("finished in %.2f s: all checks passed", took)
    return 0


if __name__ == "__main__":
    sys.exit(main())
