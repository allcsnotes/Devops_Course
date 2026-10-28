"""Course Copilot, lab copy for M09-L03 "Feature Flags" (a small, real FastAPI service).

/ask asks the AI model service (a lab stand-in) when the flag copilot-answers is on; when it is off, it answers
from the static course index instead. /lessons/{id}/notes serves Priya's new notes (v2) only to the users the flag
lesson-notes-v2 lets through. Flags are evaluated with the OpenFeature SDK and the flagd provider (RPC mode).
"""
import json
import os
import socket
import time
import urllib.request

from fastapi import FastAPI, HTTPException
from openfeature import api
from openfeature.contrib.provider.flagd import FlagdProvider
from openfeature.evaluation_context import EvaluationContext

app = FastAPI(title="Course Copilot")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")
MODEL_URL = os.environ.get("MODEL_URL", "http://model:9000/answer")
HOST = socket.gethostname()
STARTED = time.strftime("%H:%M:%S")

if os.environ.get("FLAGD_HOST"):   # FLAGD_HOST, FLAGD_PORT, FLAGD_RESOLVER come from the environment
    api.set_provider(FlagdProvider())
flags = api.get_client()


def load_index():
    with open(INDEX) as f:
        return json.load(f)


def static_help(q):
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return f"Try the {c['title']} course."
    return "AI answers are paused. Browse the course list, or try again later."


def ask_model(q):
    req = urllib.request.Request(MODEL_URL, data=json.dumps({"q": q}).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=2) as r:
        return json.load(r)["answer"]


@app.get("/health")
def health():
    return {"status": "ok", "host": HOST, "pid": os.getpid(), "started": STARTED}


@app.get("/ask")
def ask(q: str, user: str = "anonymous"):
    ctx = EvaluationContext(targeting_key=user)
    if flags.get_boolean_value("copilot-answers", True, ctx):
        try:
            return {"answer": ask_model(q), "source": "ai", "host": HOST}
        except Exception:
            raise HTTPException(502, "the AI model did not answer")
    return {"answer": static_help(q), "source": "fallback", "host": HOST}


@app.get("/lessons/{lesson}/notes")
def notes(lesson: int, user: str, role: str = "student"):
    ctx = EvaluationContext(targeting_key=user, attributes={"role": role})
    if flags.get_boolean_value("lesson-notes-v2", False, ctx):
        return {"lesson": lesson, "notes": "v2", "host": HOST}
    return {"lesson": lesson, "notes": "v1", "host": HOST}
