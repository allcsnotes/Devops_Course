"""Course Copilot stand-in (a small, real FastAPI service; no AI model). Lab only.

It answers "which course covers X?" from a course index file, and reports its health.
"""

import json
import os

from fastapi import FastAPI

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")


def load_index():
    with open(INDEX) as f:
        return json.load(f)


@app.get("/health")
def health():
    return {"status": "ok", "version": VERSION, "courses": len(load_index())}


@app.get("/ask")
def ask(q: str):
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return {"answer": f"Try the {c['title']} course."}
    return {"answer": "I could not find a course for that yet. Try asking about docker!"}
