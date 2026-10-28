from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_ask_ignores_case():
    r = client.get("/ask", params={"q": "Kubernetes"})
    assert r.json() == {"answer": "Try the DevOps course (beginner to advanced)."}


def test_ask_unknown_topic():
    r = client.get("/ask", params={"q": "cooking"})
    assert "could not find a course" in r.json()["answer"]


def test_ask_understands_a_real_question():
    r = client.get("/ask", params={"q": "What is Docker?"})
    assert r.json() == {"answer": "Try the DevOps course (beginner to advanced)."}


def test_ask_course_without_a_level():
    r = client.get("/ask", params={"q": "graphs"})
    assert r.json() == {"answer": "Try the DSA course."}
