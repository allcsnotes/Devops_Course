#!/bin/bash
# probe.sh URL: ask a URL from inside the API's network (as api1 sees it), with a 2 second limit
docker compose -f "$(dirname "$0")/compose.yaml" exec -T api1 python -c "
import sys, time, urllib.request
t = time.perf_counter()
try:
    r = urllib.request.urlopen('$1', timeout=2); print(r.status, f'{time.perf_counter() - t:.3f}s')
except Exception as e:
    print('FAILED', type(e).__name__, str(e)[:40], f'after {time.perf_counter() - t:.3f}s')"
