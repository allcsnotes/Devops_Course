"""traffic.py - simulated users for M12-B01 (adapted from M09-L02). Hits the load balancer at a steady rate and records
what came back, while Ansible rolls a release through the fleet.

  python traffic.py <url> <seconds> <out-prefix>
  - RATE requests a second on a fixed schedule, each in its own thread with a new connection (like separate users)
  - 70% ask a question (/ask?q=...), 30% read /health
  - every response is sorted by its X-App-Version and X-Served-By headers and its status code; failures with no
    response (connection refused, timeout after 2 s) count as "conn"
  - <out>.csv   one line per request:  epoch_ms,path,status,version,host,latency_ms
  - <out>.jsonl one line per second:   {"t": epoch_s, "v:1.8.0": n, "h:web-01": n, "s200": n, "s502": n, "conn": n}
"""
import http.client, json, random, signal, sys, threading, time
from collections import defaultdict
from urllib.parse import urlparse

URL, SECONDS, OUT = sys.argv[1], float(sys.argv[2]), sys.argv[3]
RATE = 40
u = urlparse(URL)
QUESTIONS = ["docker", "kubernetes basics", "graphs", "caching", "spring jpa", "rag", "linux"]
lock = threading.Lock()
per_sec = defaultdict(lambda: defaultdict(int))
rows = []
stop_at = time.time() + SECONDS


def stop_now(*_):   # docker stop: finish the requests in flight, then write the files
    global stop_at
    stop_at = 0


signal.signal(signal.SIGTERM, stop_now)


def one():
    path = f"/ask?q={random.choice(QUESTIONS).replace(' ', '+')}" if random.random() < 0.7 else "/health"
    t0 = time.time()
    try:
        c = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=2)
        c.request("GET", path)
        r = c.getresponse(); r.read()
        status, ver, host = str(r.status), r.getheader("X-App-Version", "-"), r.getheader("X-Served-By", "-")
        c.close()
    except Exception:
        status, ver, host = "conn", "-", "-"
    with lock:
        s = per_sec[int(t0)]
        s["s" + status if status != "conn" else "conn"] += 1
        if status == "200":
            s["v:" + ver] += 1
            s["h:" + host] += 1
        rows.append(f"{int(t0*1000)},{path.split('?')[0]},{status},{ver},{host},{int((time.time()-t0)*1000)}")


def schedule():
    nxt = time.time()
    while nxt < stop_at:
        time.sleep(max(0, nxt - time.time()))
        threading.Thread(target=one).start()
        nxt += 1 / RATE


sched = threading.Thread(target=schedule); sched.start()
last = int(time.time())
while sched.is_alive() or threading.active_count() > 1:
    time.sleep(0.25)
    now = int(time.time())
    with lock:
        for sec in range(last, now - 2):   # print seconds that are complete
            s = per_sec.get(sec, {})
            print(time.strftime("%H:%M:%S", time.localtime(sec)), " ".join(f"{k}={v}" for k, v in sorted(s.items())), flush=True)
        last = max(last, now - 2)
with open(OUT + ".jsonl", "w") as f:
    for sec in sorted(per_sec):
        f.write(json.dumps({"t": sec, **per_sec[sec]}) + "\n")
with open(OUT + ".csv", "w") as f:
    f.write("epoch_ms,path,status,version,host,latency_ms\n" + "\n".join(sorted(rows)) + "\n")
print("done", len(rows), "requests")
