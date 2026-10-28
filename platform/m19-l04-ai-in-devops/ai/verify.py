"""verify.py: check the assistant's claim against the real record: the request log, the deploy log, the pager log."""
import csv, json, time
fmt = lambda t: time.strftime("%H:%M:%S", time.localtime(t))
deps = [json.loads(l) for l in open("/work/lab/incident/deploys.log")]
bad = {"1.5.0": next(d for d in deps if d["version"] == "1.5.0"), "rb": next(d for d in deps if d["version"] == "1.4.2")}
rows = [(float(r[0]), r[1], r[2], int(r[3])) for r in csv.reader(open("/work/lab/runs/r1.csv"))]
win = [r for r in rows if bad["1.5.0"]["start"] - 60 <= r[0] <= bad["rb"]["epoch"] + 60]
fail = [r for r in win if r[3] == 0 or r[3] >= 500]
pages = [json.loads(l) for l in open("/work/lab/incident/notifications.log")]
page = next(p for p in pages if p["kind"] == "page" and p["status"] == "firing" and p["epoch"] > bad["1.5.0"]["start"])
print(f"{fmt(bad['1.5.0']['start'])}  deploy catalog-api 1.5.0 started (priya)")
print(f"{fmt(fail[0][0])}  first failed request ({fail[0][1]} {fail[0][2]})")
print(f"{fmt(page['epoch'])}  first page: {page['group']['alertname']} {page['group']['service']}")
print(f"{fmt(bad['rb']['start'])}  rollback to 1.4.2 started (asha)")
print(f"{fmt(fail[-1][0])}  last failed request")
before = [r for r in rows if r[0] < bad["1.5.0"]["start"] and r[0] > bad["1.5.0"]["start"] - 1800]
print(f"failed in the 30 min before the deploy: {sum(1 for r in before if r[3] == 0 or r[3] >= 500)} of {len(before)}")
imp = [r for r in rows if fail[0][0] <= r[0] <= fail[-1][0]]
print(f"during the impact: {len(fail)} of {len(imp)} requests failed ({100 * len(fail) / len(imp):.1f}%)")
