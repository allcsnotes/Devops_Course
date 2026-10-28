"""course-search: a small FastAPI service for the take-home (keyword search, no AI model).

GET /health          {"status": "ok", "version": ..., "courses": N}
GET /search?q=WORDS  the courses whose topics match any word
Config: APP_VERSION (default "dev"), COURSE_INDEX (default data/courses.json)
"""
import json
import os

from fastapi import FastAPI, Response

app = FastAPI(title="course-search")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")


def load_index():
    with open(INDEX, encoding="utf-8") as f:
        return json.load(f)


@app.get("/health")
def health(response: Response):
    try:
        courses = load_index()
    except OSError:
        response.status_code = 503
        return {"status": "degraded", "error": "course index not found"}
    return {"status": "ok", "version": VERSION, "courses": len(courses)}


@app.get("/search")
def search(q: str):
    words = set(q.split())
    hits = [c["title"] for c in load_index() if words & set(c["topics"])]
    return {"query": q, "results": hits}
