"""Course Copilot 1.6.0 (lab copy for M09-L02; a small, real FastAPI service, no AI model)."""
import json
import os

from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse

app = FastAPI(title="Course Copilot")
VERSION = os.environ.get("APP_VERSION", "dev")
INDEX = os.environ.get("COURSE_INDEX", "data/courses.json")
COLOUR = "#1a7cff"   # 1.6.0: blue banner


def load_index():
    with open(INDEX) as f:
        return json.load(f)


@app.middleware("http")
async def version_header(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-App-Version"] = VERSION   # so every response says which build answered
    return response


@app.get("/", response_class=HTMLResponse)
def home():
    return f'<body style="margin:0;font-family:sans-serif"><div style="background:{COLOUR};color:#fff;padding:24px">Course Copilot {VERSION}</div></body>'


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
    return {"version": VERSION}


@app.get("/ask")
def ask(q: str):
    words = q.lower().split()
    for c in load_index():
        if any(w in c["topics"] for w in words):
            return {"answer": f"Try the {c['title']} course."}
    return {"answer": "I could not find a course for that yet. Try asking about docker!"}
