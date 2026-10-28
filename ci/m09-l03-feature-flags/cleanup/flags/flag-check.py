#!/usr/bin/env python3
"""flag-check: keep feature flags from turning into debt. Runs in CI on every push.

usage: flag-check.py FLAGS_YAML REMOVED_TXT
  1. every flag has an owner and a type; release and experiment flags also need an expiry date
  2. a flag past its expiry date fails the check
  3. a removed flag (one name per line in REMOVED_TXT) that is still referenced anywhere in the repository fails too
"""
import datetime
import subprocess
import sys

import yaml

flags = yaml.safe_load(open(sys.argv[1]))["flags"]
removed = [l.split("#")[0].strip() for l in open(sys.argv[2]) if l.split("#")[0].strip()]
today = datetime.date.today()
problems = 0
print(f"flag-check {today}: {len(flags)} flags, {len(removed)} removed")
for key, f in flags.items():
    m = f.get("metadata") or {}
    owner, kind, exp = m.get("owner"), m.get("type"), m.get("expires")
    if not owner or not kind or (kind in ("release", "experiment") and not exp):
        print(f"  MISSING  {key:16} needs owner, type and (release/experiment) expires")
        problems += 1
    elif exp and datetime.date.fromisoformat(str(exp)) < today:
        print(f"  EXPIRED  {key:16} {kind:8} owner {owner:6} expired {exp}")
        problems += 1
    else:
        print(f"  ok       {key:16} {kind:8} owner {owner:6} {'expires ' + str(exp) if exp else ''}".rstrip())
for name in removed:
    hits = subprocess.run(["git", "grep", "-n", "-w", name, "--", ".", ":!flags/"],
                          capture_output=True, text=True).stdout.splitlines()
    for h in hits:
        print(f"  REMOVED  {name} is still referenced: {h[:60]}")
        problems += 1
    if not hits:
        print(f"  gone     {name} (no references left)")
if problems:
    print(f"FAIL: {problems} problem{'s' if problems > 1 else ''}")
    sys.exit(1)
print("PASS")
