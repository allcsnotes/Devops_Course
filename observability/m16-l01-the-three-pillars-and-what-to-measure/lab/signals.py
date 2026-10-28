"""signals.py <run> [section] - the four golden signals, RED and USE, computed from one real lab run.

Inputs (runs/): <run>.csv        one line per request, as the users saw it: epoch_ms,route,status,latency_ms
                <run>-pool.csv   the API's own /metrics, once a second: epoch_ms,in_use,waiting   (pool size 4)
                <run>-stats.csv  docker stats, about once a second: epoch_ms,container,cpu%,used / limit,mem%
                runs/<run>-migration.txt     start / end time of the staged migration
Windows: "before" = first request .. migration start · "during" = migration start .. end · "after" = end .. last request
Sections: golden | red | use | avg | all (default). Also writes runs/<run>-summary.json.
"""
import csv, json, os, re, sys, time
from statistics import mean

D = os.path.dirname(os.path.abspath(__file__))
RUN = sys.argv[1]; SEC = sys.argv[2] if len(sys.argv) > 2 else "all"
POOL = 4
req = [(int(a) / 1000, r, s, int(l)) for a, r, s, l in csv.reader(open(f"{D}/runs/{RUN}.csv")) if a]
pool = [(int(a) / 1000, int(u), int(w)) for a, u, w in csv.reader(open(f"{D}/runs/{RUN}-pool.csv")) if a and u]
stats = []
for a, name, cpu, mem, memp in csv.reader(open(f"{D}/runs/{RUN}-stats.csv")):
    used = mem.split(" / ")[0]; mib = float(used[:-3]) * (1024 if used.endswith("GiB") else 1)
    stats.append((int(a) / 1000, name.replace("m16-lab-", "").replace("-1", ""), float(cpu[:-1]), mib, float(memp[:-1])))
mig = open(f"{D}/runs/{RUN}-migration.txt").read()
day = time.strftime("%Y-%m-%d", time.localtime(req[0][0]))
ep = lambda hms: time.mktime(time.strptime(day + " " + hms, "%Y-%m-%d %H:%M:%S"))
m0, m1 = ep(re.search(r"start (\S+)", mig).group(1)), ep(re.search(r"end (\S+)", mig).group(1))
t0, t9 = req[0][0], req[-1][0] + 1
WIN = [("before", t0, m0), ("during", m0, m1), ("after", m1, t9)]


def pct(v, p):
    v = sorted(v); return v[min(len(v) - 1, int(p * len(v)))] if v else 0


def ms(x):
    return f"{x / 1000:.2f} s" if x >= 1000 else f"{x:.0f} ms"


def inw(rows, a, b): return [r for r in rows if a <= r[0] < b]


out = {"t0": int(t0), "m0": m0 - t0, "m1": m1 - t0, "windows": {}, "sec": [], "pool": [], "stats": []}
G = []
for name, a, b in WIN:
    R = inw(req, a, b); L = [r[3] for r in R]; bad = [r for r in R if r[2] != "200"]; P = inw(pool, a, b)
    g = dict(seconds=round(b - a), requests=len(R), rps=len(R) / (b - a), errors=len(bad), err_pct=100 * len(bad) / len(R),
             mean=mean(L), p50=pct(L, .5), p95=pct(L, .95), p99=pct(L, .99), max=max(L),
             pool_use=100 * mean(p[1] for p in P) / POOL, pool_wait=mean(p[2] for p in P), pool_wait_max=max(p[2] for p in P),
             status={s: sum(1 for r in R if r[2] == s) for s in sorted({r[2] for r in R})})
    for c in ("api", "db"):
        S = [s for s in inw(stats, a, b) if s[1] == c]
        g[c] = dict(cpu=mean(s[2] for s in S), cpu_max=max(s[2] for s in S), mem=mean(s[3] for s in S), memp=mean(s[4] for s in S))
    for route in ("list", "popular"):
        RR = [r for r in R if r[1] == route]; LL = [r[3] for r in RR]
        g[route] = dict(rate=len(RR) / (b - a), errors=sum(1 for r in RR if r[2] != "200"), n=len(RR),
                        p50=pct(LL, .5), p99=pct(LL, .99), mean=mean(LL) if LL else 0)
    out["windows"][name] = g; G.append((name, g))
n = int(t9 - t0)
for i in range(n):
    R = [r for r in req if int(r[0] - t0) == i]; L = [r[3] for r in R]
    out["sec"].append([len(R), sum(1 for r in R if r[2] != "200"), round(mean(L), 1) if L else None, pct(L, .5), pct(L, .99)])
out["pool"] = [[round(p[0] - t0, 2), p[1], p[2]] for p in pool]
out["stats"] = [[round(s[0] - t0, 2), s[1], s[2], round(s[3], 1)] for s in stats]
json.dump(out, open(f"{D}/runs/{RUN}-summary.json", "w"))

hdr = f"{'':22}" + "".join(f"{n:>13}" for n, _ in G)
row = lambda label, f: print(f"{label:22}" + "".join(f"{f(g):>13}" for _, g in G))
print(f"run {RUN}: {len(req)} requests · migration {time.strftime('%H:%M:%S', time.localtime(m0))}-{time.strftime('%H:%M:%S', time.localtime(m1))}")
if SEC in ("golden", "all"):
    print("\nFOUR GOLDEN SIGNALS (as the users saw it)"); print(hdr)
    row("latency p50", lambda g: ms(g["p50"])); row("latency p95", lambda g: ms(g["p95"])); row("latency p99", lambda g: ms(g["p99"]))
    row("traffic (req/s)", lambda g: f"{g['rps']:.1f}"); row("errors", lambda g: f"{g['err_pct']:.1f} %")
    row("saturation (pool)", lambda g: f"{g['pool_use']:.0f} % used"); row("  waiting for a conn", lambda g: f"{g['pool_wait']:.1f}")
if SEC in ("red", "all"):
    print("\nRED per endpoint"); print(hdr)
    for route, lbl in (("list", "/api/courses"), ("popular", "?sort=popular")):
        print(lbl)
        row("  rate (req/s)", lambda g: f"{g[route]['rate']:.2f}"); row("  errors", lambda g: f"{g[route]['errors']} of {g[route]['n']}")
        row("  duration p99", lambda g: ms(g[route]["p99"]))
if SEC in ("use", "all"):
    print("\nUSE per resource"); print(hdr)
    print("db connection pool (4)")
    row("  utilization", lambda g: f"{g['pool_use']:.0f} %"); row("  saturation (waiting)", lambda g: f"{g['pool_wait']:.1f}")
    row("  errors (503 timeout)", lambda g: str(g["status"].get("503", 0)))
    for c in ("api", "db"):
        print(f"{c} container (1 CPU)")
        row("  CPU utilization", lambda g: f"{g[c]['cpu']:.1f} %"); row("  memory", lambda g: f"{g[c]['mem']:.0f} MiB")
if SEC in ("avg", "all"):
    print("\nMEAN vs PERCENTILES (same requests)"); print(hdr)
    row("mean", lambda g: ms(g["mean"])); row("p50", lambda g: ms(g["p50"])); row("p99", lambda g: ms(g["p99"])); row("max", lambda g: ms(g["max"]))
