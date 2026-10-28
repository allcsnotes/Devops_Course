"""Course Copilot stand-in (a small, real FastAPI service; no AI model). Lab only.

It answers "which course covers X?" from a course index file, and reports its health.
"""

import json
import os
import sqlite3

import yaml
from fastapi import FastAPI

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")
CATALOG = os.environ.get("CATALOG", "data/catalog.yaml")


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


def catalog_db():
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE courses (title TEXT, price INTEGER)")
    with open(CATALOG) as f:
        rows = [(c["title"], c["price"]) for c in yaml.load(f, Loader=yaml.SafeLoader)]
    db.executemany("INSERT INTO courses VALUES (?, ?)", rows)
    return db


@app.get("/courses/search")
def search(q: str):
    # DELIBERATELY VULNERABLE (lab only): the user's text is pasted into the SQL
    sql = f"SELECT title, price FROM courses WHERE title LIKE '%{q}%'"
    rows = catalog_db().execute(sql).fetchall()
    return [{"title": t, "price": p} for t, p in rows]
