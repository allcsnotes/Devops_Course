"""guard.py ACTION...: the only way the assistant's suggestions reach a shell. Read-only commands on the allowlist run;
anything else is printed as a proposal and waits for a human to type yes. Default: no."""
import subprocess, sys
READ_ONLY = {"curl -sG prometheus:9090/api/v1/query", "curl -s alertmanager:9093/api/v2/alerts", "tail incident/deploys.log",
             "grep", "jq"}
argv = sys.argv[1:]; cmd = " ".join(argv)
if any(cmd.startswith(p) for p in READ_ONLY) and not any(c in cmd for c in [";", "&&", "|", ">", "`", "$("]):
    print(f"allowed (read-only): {cmd}", file=sys.stderr, flush=True); sys.exit(subprocess.call(argv))
print(f"BLOCKED: not on the read-only allowlist: {cmd}")
print("This changes production. Proposal for the on-call engineer. Run it? [y/N] ", end="", flush=True)
ans = sys.stdin.readline().strip().lower()
if not sys.stdin.isatty(): print(ans)   # show the typed answer in captures
print("approved by a human: run it yourself, after checking" if ans == "y" else "not run")
