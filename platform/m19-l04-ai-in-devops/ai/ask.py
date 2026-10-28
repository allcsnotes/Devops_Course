"""ask.py: send one prompt to the lab's small local model and print the answer, verbatim, plus the real stats.
  python3 ask.py PROMPT_FILE [--system FILE] [--ctx N] [--schema FILE] [--out NAME]
Model: llama3.2:3b (Q4_K_M) on Ollama 0.40.6, CPU only, 4 CPUs, 4 GB memory limit, on an internal network.
temperature 0 and a fixed seed, so a rerun gives the same answer on this machine (not guaranteed elsewhere).
num_thread 4 matches the container's CPU limit: with the default (one thread per visible core, 10 here)
the same prompt decoded at about 0.2 tokens a second instead of about 25.
use_mmap off: the weights are read into the runner once; with mmap, the file pages and the repacked copy together
pushed the runner past the 4 GB limit (the kernel killed it, Ollama answered HTTP 500)."""
import argparse, json, time, urllib.request

p = argparse.ArgumentParser()
p.add_argument("prompt"); p.add_argument("--system"); p.add_argument("--ctx", type=int, default=0)
p.add_argument("--schema"); p.add_argument("--out"); p.add_argument("--model", default="llama3.2:3b")
a = p.parse_args()
msgs = []
if a.system:
    msgs.append({"role": "system", "content": open(a.system).read()})
msgs.append({"role": "user", "content": open(a.prompt).read()})
opt = {"temperature": 0, "seed": 42, "num_thread": 4, "use_mmap": False}
if a.ctx:
    opt["num_ctx"] = a.ctx
req = {"model": a.model, "messages": msgs, "stream": False, "options": opt}
if a.schema:
    req["format"] = json.load(open(a.schema))
t0 = time.time()
r = json.load(urllib.request.urlopen(urllib.request.Request("http://ollama:11434/api/chat", json.dumps(req).encode(),
                                                            {"Content-Type": "application/json"}), timeout=1800))
if a.out:
    json.dump({"request": req, "response": r}, open(f"/work/outputs/{a.out}.json", "w"), indent=1)
print(r["message"]["content"].strip())
print(f"\n[{a.model} · context {opt.get('num_ctx', 'default 4096')} · read {r.get('prompt_eval_count')} prompt tokens"
      f" · wrote {r.get('eval_count')} tokens · {time.time() - t0:.1f} s]")
