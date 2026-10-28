"""timings.py: the real cost of each answer in this lesson, from Ollama's own stats (llama3.2:3b, 4 CPUs, no GPU)."""
import json
rows = [("naive 2 a.m. question", "naive"), ("grounded triage bundle", "triage"), ("raw CI log", "ci1"), ("trimmed CI log", "ci2"), ("postmortem draft", "pm1")]
print(f"{'request':24} {'read':>6} {'wrote':>6} {'seconds':>8}  tokens/s read · written")
for name, f in rows:
    r = json.load(open(f"/work/outputs/{f}.json"))["response"]
    pe, ec = r["prompt_eval_count"], r["eval_count"]
    print(f"{name:24} {pe:6} {ec:6} {r['total_duration'] / 1e9:8.1f}  {pe / (r['prompt_eval_duration'] / 1e9):5.1f} · {ec / (r['eval_duration'] / 1e9):4.1f}")
