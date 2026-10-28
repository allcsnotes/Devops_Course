#!/usr/bin/env python3
# logstats.py: what is in the nginx logs, and how full is that disk?
import shutil
from collections import Counter
from pathlib import Path

logs = Path("/var/log/nginx")
for path in sorted(logs.glob("*.log")):
    print(f"{path.name:<11} {path.stat().st_size:>9,} bytes")

statuses, errors = Counter(), Counter()
with (logs / "access.log").open() as f:
    for line in f:
        fields = line.split()
        status, url = fields[8], fields[6]
        statuses[status] += 1
        if status.startswith("5"):
            errors[url] += 1

print("status codes:", dict(statuses.most_common()))
print("5xx by path: ", errors.most_common(3))

usage = shutil.disk_usage(logs)
print(f"disk: {usage.used / usage.total:.1%} used,",
      f"{usage.free // 2**30:,} GiB free")
