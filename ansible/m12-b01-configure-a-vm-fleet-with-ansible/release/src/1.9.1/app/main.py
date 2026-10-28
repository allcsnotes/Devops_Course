"""Course Copilot 1.9.1 (from the platform repo, _platform/copilot; a small, real FastAPI service, no AI model).

It answers "which course covers X?" from a course index file, and reports its health.
Runs on each web server as a systemd service (M12-B01). Config from the environment:
  APP_VERSION    shown by /health and in the X-App-Version header
  COURSE_INDEX   path to the course index (default data/courses.json, relative to the release folder)
"""
import json
import os
import socket

from fastapi import FastAPI, Request, Response

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")
HOST = socket.gethostname()


def load_index():
    with open(INDEX) as f:
        return json.load(f)


@app.middleware("http")
async def stamp(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-App-Version"] = VERSION   # which release answered
    response.headers["X-Served-By"] = HOST        # which web server answered
    return response


@app.get("/health")
def health(response: Response):
    try:
        courses = load_index()
    except OSError:
        response.status_code = 503
        return {"status": "degraded", "error": "course index not found", "version": VERSION}
    return {"status": "ok", "version": VERSION, "host": HOST, "courses": len(courses)}


@app.get("/ask")
def ask(q: str):
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return {"answer": f"Try the {c['title']} course.", "course": c["title"]}   # 1.9.0: names the course
    return {"answer": "Hi from Course Copilot! I could not find a course for that yet. Try asking about docker!"}
