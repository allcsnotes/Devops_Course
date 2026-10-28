#!/usr/bin/env python3
"""http_check.py TIMEOUT NAME=URL...: one result line per endpoint.

Prints SEVERITY <tab> CHECK <tab> DETAIL, like the Bash checks.
CRIT: no answer, or an HTTP error. WARN: JSON "status" is not "ok".
"""
import json
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def check(name, url, timeout):
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            status, body = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return "CRIT", name, f"HTTP {e.code}"
    except urllib.error.URLError as e:
        return "CRIT", name, f"unreachable: {e.reason}"
    except TimeoutError:
        return "CRIT", name, f"no answer in {timeout:g} s"
    ms = (time.perf_counter() - start) * 1000
    detail = f"HTTP {status} in {ms:.0f} ms"
    try:
        state = json.loads(body).get("status", "ok")
    except (ValueError, AttributeError):
        return "OK", name, detail        # not JSON: a web page
    if state != "ok":
        return "WARN", name, f"{detail}, status {state}"
    return "OK", name, detail


def main():
    timeout = float(sys.argv[1])
    endpoints = [arg.split("=", 1) for arg in sys.argv[2:]]
    with ThreadPoolExecutor(max_workers=8) as pool:
        for row in pool.map(lambda ep: check(*ep, timeout), endpoints):
            print("\t".join(row))


if __name__ == "__main__":
    main()
