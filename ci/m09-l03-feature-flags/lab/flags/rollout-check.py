#!/usr/bin/env python3
"""rollout-check: ask Course Copilot which notes each of the 1000 lab users gets, and compare with a saved run.

usage: rollout-check.py SAVE_AS [COMPARE_WITH]
Users u0001-u0005 are staff, u0006-u0025 beta testers, the rest students (the same as the traffic generator).
"""
import json
import sys
import urllib.request

save = sys.argv[1]
old = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else None
got, count = {}, {"staff": [0, 0], "beta": [0, 0], "student": [0, 0]}
for n in range(1, 1001):
    user, role = f"u{n:04d}", "staff" if n <= 5 else "beta" if n <= 25 else "student"
    with urllib.request.urlopen(f"http://lb/lessons/7/notes?user={user}&role={role}") as r:
        got[user] = json.load(r)["notes"]
    count[role][0] += got[user] == "v2"
    count[role][1] += 1
json.dump(got, open(save, "w"))
v2 = sum(v == "v2" for v in got.values())
print(f"1000 users: v2 {v2}, v1 {1000 - v2}")
print("  " + " · ".join(f"{r} {a}/{b}" for r, (a, b) in count.items()))
if old:
    kept = sum(1 for u in got if old[u] == "v2" and got[u] == "v2")
    lost = sum(1 for u in got if old[u] == "v2" and got[u] == "v1")
    new = sum(1 for u in got if old[u] == "v1" and got[u] == "v2")
    print(f"vs {sys.argv[2]}: kept v2 {kept}, lost v2 {lost}, new v2 {new}")
