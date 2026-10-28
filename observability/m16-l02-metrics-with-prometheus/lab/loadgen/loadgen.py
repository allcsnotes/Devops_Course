"""Lab load generator: students asking Course Copilot questions. Python standard library only.

  RATE    requests a second, spread over the targets (default 10)
  USERS   how many different students ask (default 50); each request sends ?user=u<number>
  TARGETS comma-separated base URLs (default http://copilot-1:8000,http://copilot-2:8000)
Prints one summary line every 10 seconds.
"""
import os, random, threading, time, urllib.error, urllib.parse, urllib.request

RATE = float(os.environ.get("RATE", "10"))
USERS = int(os.environ.get("USERS", "50"))
TARGETS = os.environ.get("TARGETS", "http://copilot-1:8000,http://copilot-2:8000").split(",")
QUESTIONS = ["docker compose", "kubernetes pods", "graphs and trees", "caching", "spring jpa",
             "rag with embeddings", "terraform state", "how do I pass interviews"]
stats = {"ok": 0, "err": 0}
lock = threading.Lock()


def one(i):
    base = TARGETS[i % len(TARGETS)]
    q = urllib.parse.urlencode({"q": random.choice(QUESTIONS), "user": f"u{random.randint(1, USERS):05d}"})
    try:
        urllib.request.urlopen(f"{base}/ask?{q}", timeout=5).read()
        key = "ok"
    except (urllib.error.URLError, OSError):
        key = "err"
    with lock:
        stats[key] += 1


def main():
    print(f"loadgen: {RATE:g} req/s, {USERS} users, targets {','.join(TARGETS)}", flush=True)
    i, start, last = 0, time.time(), time.time()
    while True:
        threading.Thread(target=one, args=(i,), daemon=True).start()
        i += 1
        time.sleep(max(0, start + i / RATE - time.time()))
        if time.time() - last >= 10:
            last = time.time()
            with lock:
                print(time.strftime("%H:%M:%S"), f"sent {i}  ok {stats['ok']}  failed {stats['err']}", flush=True)


if __name__ == "__main__":
    main()
