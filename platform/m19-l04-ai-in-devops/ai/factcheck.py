"""factcheck.py DRAFT SOURCE: check a model's postmortem draft against the real timeline it was given.
Every timeline bullet in the draft (HH:MM:SS: text) must match a source line with the same time and most of the
same words (75%, first 6 letters of each word); every number in the draft must appear in the source. It finds copying errors, not bad judgement:
a human still reads the whole draft."""
import re, sys
draft, src = open(sys.argv[1]).read(), open(sys.argv[2]).read()
words = lambda s: {w[:6] for w in re.findall(r"[a-z]{4,}", s.lower())} - {"with", "from", "that", "this", "starte", "finish"}
by_time = {}
for l in src.splitlines():
    m = re.match(r"(\d\d:\d\d:\d\d)\s", l)
    if m: by_time.setdefault(m.group(1), []).append(l)
bad = ok = 0
for m in re.finditer(r"(\d\d:\d\d:\d\d):?\s+(.*)", draft):
    t, text = m.groups(); w = words(text)
    best = max((len(w & words(s)) / max(1, len(w)) for s in by_time.get(t, [])), default=0)
    if best >= 0.75: ok += 1
    else:
        bad += 1; print(f"NOT IN SOURCE  {t}  {text.strip()[:80]}")
nums = set(re.findall(r"\d[\d,.]*%?", re.sub(r"\d\d:\d\d:\d\d", "", draft)))
missing = sorted(n for n in nums if n.rstrip(".,") not in src)
print(f"{ok} timeline lines match the source, {bad} do not · numbers not in the source: {', '.join(missing) or 'none'}")
