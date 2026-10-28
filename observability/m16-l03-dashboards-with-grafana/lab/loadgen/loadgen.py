"""Lab load generator (M16-L03): students using allcsvideos. Python standard library only.

  API_RATE      requests a second to the API, spread over api-1 and api-2 (default 8)
  POPULAR       share of API requests that ask for ?sort=popular (default 0.02)
  COPILOT_RATE  questions a second to Course Copilot (default 2)
Every request has a 2-second client timeout. Prints one summary line every 10 seconds.
"""
import os, random, threading, time, urllib.error, urllib.parse, urllib.request

API_RATE = float(os.environ.get("API_RATE", "8"))
POPULAR = float(os.environ.get("POPULAR", "0.02"))
COPILOT_RATE = float(os.environ.get("COPILOT_RATE", "2"))
API = ["http://api-1:8080", "http://api-2:8080"]
QUESTIONS = ["docker compose", "kubernetes pods", "graphs and trees", "caching", "spring jpa",
             "rag with embeddings", "terraform state", "how do I pass interviews"]
stats = {"ok": 0, "err": 0}
lock = threading.Lock()


def hit(url):
    try:
        urllib.request.urlopen(url, timeout=2).read()
        key = "ok"
    except (urllib.error.URLError, OSError):
        key = "err"
    with lock:
        stats[key] += 1


def api(i):
    sort = "?sort=popular" if random.random() < POPULAR else ""
    hit(f"{API[i % 2]}/api/courses{sort}")


def copilot(i):
    hit("http://copilot:8000/ask?" + urllib.parse.urlencode({"q": random.choice(QUESTIONS)}))


def loop(fn, rate):
    i, start = 0, time.time()
    while True:
        threading.Thread(target=fn, args=(i,), daemon=True).start()
        i += 1
        time.sleep(max(0, start + i / rate - time.time()))


def main():
    print(f"loadgen: api {API_RATE:g} req/s ({POPULAR:.0%} popular), copilot {COPILOT_RATE:g} req/s", flush=True)
    threading.Thread(target=loop, args=(api, API_RATE), daemon=True).start()
    threading.Thread(target=loop, args=(copilot, COPILOT_RATE), daemon=True).start()
    while True:
        time.sleep(10)
        with lock:
            print(time.strftime("%H:%M:%S"), f"ok {stats['ok']}  failed {stats['err']}", flush=True)


if __name__ == "__main__":
    main()
