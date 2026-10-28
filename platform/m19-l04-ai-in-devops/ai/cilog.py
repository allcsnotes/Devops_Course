"""cilog.py LOG WORKFLOW JOB: cut a CI job log down to what matters before asking a model: drop the timestamps and the
runner/checkout noise, keep the failing step's output, and add that step's definition from the workflow file."""
import re, sys
log, wf, job = sys.argv[1:4]
L = [re.sub(r"^\S+Z ", "", l.rstrip("\n")) for l in open(log)]
end = next(i for i, l in enumerate(L) if "##[error]" in l)
start = max(i for i, l in enumerate(L[:end]) if l.startswith("::endgroup::")) + 1   # after the last setup group
keep = [l for l in L[start:end + 1] if l.strip() and "VEX" not in l and "TRIVY_DISABLE_VEX" not in l
        and "vulnerabilities in your project" not in l and not l.startswith("---")]
W = open(wf).read().splitlines()
a = next(i for i, l in enumerate(W) if l.strip() == job + ":")
b = next((i for i in range(a + 1, len(W)) if re.match(r"^  \S", W[i])), len(W))
print(f"JOB DEFINITION ({wf.split('/')[-1]}):"); print("\n".join(W[a:b]).rstrip())
print(f"\nFAILING STEP OUTPUT ({len(keep)} of {len(L)} log lines kept):"); print("\n".join(keep))
