"""Course Copilot stand-in (a small, real FastAPI service; no AI model).

It answers "which course covers X?" from a course index file, and reports its health.
Config comes from environment variables:
  APP_VERSION        shown by /health and /version  (image default: set at build time)
  APP_REVISION       the Git commit it was built from (image default: set at build time)
  APP_ENV            which environment runs it       (set by the deploy, per environment)
  APP_COLOUR         blue or green                   (set by the deploy)
  IMAGE_DIGEST       this image's digest             (set by the deploy)
  STOREFRONT_DIGEST  the storefront image it ships with (set by the deploy)
  COURSE_INDEX       path to the course index        (image default /app/data/courses.json)
  DATABASE_URL       PostgreSQL, for /price          (e.g. postgresql://user:pass@db/allcsvideos)
  REDIS_URL          Redis, for /price               (e.g. redis://redis:6379/0)
"""

import json
import os
import re

import psycopg
import redis
from fastapi import FastAPI, HTTPException, Request, Response

from app.catalog import Catalog

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")


def load_index():
    with open(INDEX) as f:
        return json.load(f)


@app.middleware("http")
async def version_header(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-App-Version"] = VERSION  # every response says which build answered
    return response


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
    return {
        "version": VERSION,
        "revision": os.environ.get("APP_REVISION", "unknown"),
        "environment": os.environ.get("APP_ENV", "dev"),
        "colour": os.environ.get("APP_COLOUR", "none"),
        "copilot": os.environ.get("IMAGE_DIGEST", "unknown"),
        "storefront": os.environ.get("STOREFRONT_DIGEST", "unknown"),
    }


@app.get("/ask")
def ask(q: str):
    words = re.findall(r"[a-z0-9]+", q.lower())  # "What is Docker?" -> what, is, docker
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
