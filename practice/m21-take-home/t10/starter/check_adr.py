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
