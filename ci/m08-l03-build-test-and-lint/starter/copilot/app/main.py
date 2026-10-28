"""Course Copilot stand-in (a small, real FastAPI service; no AI model).

It answers "which course covers X?" from a course index file, and reports its health.
Config comes from environment variables:
  APP_VERSION    shown by /health            (image default: set at build time)
  COURSE_INDEX   path to the course index    (image default /app/data/courses.json)
  DATABASE_URL   PostgreSQL, for /price      (e.g. postgresql://user:pass@db/allcsvideos)
  REDIS_URL      Redis, for /price           (e.g. redis://redis:6379/0)
"""

import json
import os

import psycopg
import redis
from fastapi import FastAPI, HTTPException, Response

from app.catalog import Catalog

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")


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


@app.get("/ask")
def ask(q: str):
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return {"answer": f"Try the {c['title']} course."}
    return {
        "answer": "Hi from Course Copilot! I could not find a course for that yet. "
        "Try asking about docker!"
    }


@app.get("/price")
def price(title: str):
    with psycopg.connect(os.environ["DATABASE_URL"]) as db:
        catalog = Catalog(db, redis.Redis.from_url(os.environ["REDIS_URL"]))
        rupees = catalog.price(title)
    if rupees is None:
        raise HTTPException(status_code=404, detail="no such course")
    return {"title": title, "price": rupees}
