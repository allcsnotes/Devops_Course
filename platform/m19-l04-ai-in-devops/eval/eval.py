"""eval.py: evaluate before you trust. 15 past incidents from this course's own labs, each with a known root cause.
The model gets only the evidence, answers in a fixed JSON shape, and a keyword rule (written before any run) scores
its root_cause: a hit needs one word from every keyword group. Prints one row per case and the score."""
import json, time, urllib.request

SYS = ("You are an SRE assistant. From the evidence, name the single most likely root cause in one sentence. "
       "Use only the evidence. If the evidence is not enough, say unknown.")
SCHEMA = {"type": "object", "properties": {"root_cause": {"type": "string"}, "evidence_line": {"type": "string"}},
          "required": ["root_cause", "evidence_line"]}
cases = json.load(open("/work/eval/cases.json")); hits, rows, t0 = 0, [], time.time()
for c in cases:
    req = {"model": "llama3.2:3b", "stream": False, "format": SCHEMA, "options": {"temperature": 0, "seed": 42, "num_thread": 4},
           "messages": [{"role": "system", "content": SYS}, {"role": "user", "content": "EVIDENCE:\n" + c["evidence"]}]}
    r = json.load(urllib.request.urlopen(urllib.request.Request("http://ollama:11434/api/chat", json.dumps(req).encode(),
                                                                {"Content-Type": "application/json"}), timeout=900))
    ans = json.loads(r["message"]["content"])
    rc = ans.get("root_cause", "").lower()
    ok = all(any(k in rc for k in grp) for grp in c["keywords"])
    hits += ok
    rows.append({"id": c["id"], "hit": ok, "model": ans.get("root_cause", ""), "truth": c["root_cause"]})
    print(f"{'HIT ' if ok else 'MISS'}  {c['id']:17} {ans.get('root_cause', '')[:150]}", flush=True)
json.dump(rows, open("/work/outputs/eval_rows.json", "w"), indent=1)
print(f"\n{hits} of {len(cases)} root causes found ({100 * hits / len(cases):.0f}%) · llama3.2:3b · {time.time() - t0:.0f} s")
