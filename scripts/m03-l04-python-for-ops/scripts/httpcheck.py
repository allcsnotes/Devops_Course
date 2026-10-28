#!/usr/bin/env python3
# httpcheck.py: one HTTP check, with a timeout and honest errors
import sys
import time
import urllib.error
import urllib.request

url = sys.argv[1]
start = time.perf_counter()
try:
    with urllib.request.urlopen(url, timeout=3) as resp:
        print(f"HTTP {resp.status}", end="")
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code} {e.reason}", end="")
except urllib.error.URLError as e:
    print(f"unreachable: {e.reason}", end="")
except TimeoutError:
    print("timed out", end="")
print(f" after {time.perf_counter() - start:.2f} s")
