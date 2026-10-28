"""Course Copilot stand-in for M06-L04 (a small, real FastAPI service; no AI model).

It answers "which course covers X?" from a course index file, and reports its health.
Config comes from environment variables:
  APP_VERSION    shown by /health and /version   (image default: set at build time)
  APP_REVISION   the Git commit it was built from (image default: set at build time)
  APP_ENV        which environment runs it    (set by the deploy, per environment)
  IMAGE_DIGEST   the image digest it runs from (set by the deploy)
  COURSE_INDEX   path to the course index     (image default /app/data/courses.json)
"""
import json
import os

from fastapi import FastAPI, Response

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")
REVISION = os.environ.get("APP_REVISION", "unknown")
ENVIRONMENT = os.environ.get("APP_ENV", "dev")
DIGEST = os.environ.get("IMAGE_DIGEST", "unknown")


def load_index():
    with open(INDEX) as f:
        return json.load(f)


@app.get("/health")
def health(response: Response):
    try:
        courses = load_index()
    except OSError:
        response.status_code = 503
        return {"status": "degraded", "error": "course index not found"}
    return {"status": "ok", "version": VERSION, "courses": len(courses)}


@app.get("/version")
def version():
    return {"version": VERSION, "revision": REVISION, "environment": ENVIRONMENT, "digest": DIGEST}


@app.get("/ask")
def ask(q: str):
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return {"answer": f"Try the {c['title']} course."}
    return {"answer": "Hi from Course Copilot! I could not find a course for that yet. Try asking about docker!"}
