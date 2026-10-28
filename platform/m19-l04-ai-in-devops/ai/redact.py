"""redact.py IN OUT: remove secrets and personal data from logs BEFORE any model sees them (even a local one).
Replaces each match with a tag, and prints how many of each kind it removed. Patterns, not magic: review the
output, and add a pattern whenever a new kind of leak shows up (module 18, lesson 2)."""
import re, sys
from collections import Counter

RULES = [
    ("email", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("password-in-url", re.compile(r"(?<=://)([^:/@\s]+):([^@\s]+)(?=@)")),
    ("api-key", re.compile(r'(?i)("?[\w-]*(?:api[_-]?key|token|secret|password)"?\s*[:=]\s*"?)([^",\s}]+)')),
    ("aws-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
]
n = Counter()


def clean(line):
    for kind, rx in RULES:
        def sub(m, kind=kind):
            n[kind] += 1
            if kind == "api-key":
                return m.group(1) + "[REDACTED:" + kind + "]"
            if kind == "password-in-url":
                return m.group(1) + ":[REDACTED:password]"
            return "[REDACTED:" + kind + "]"
        line = rx.sub(sub, line)
    return line


with open(sys.argv[1]) as f, open(sys.argv[2], "w") as o:
    lines = 0
    for line in f:
        o.write(clean(line)); lines += 1
print(f"{lines} lines read, " + (", ".join(f"{v} {k}" for k, v in n.most_common()) or "nothing") + " redacted")
