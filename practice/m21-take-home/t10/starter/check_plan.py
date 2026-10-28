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
