from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_reports_courses():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["courses"] == 5


def test_ask_finds_devops():
    r = client.get("/ask", params={"q": "docker"})
    assert r.json() == {"answer": "Try the DevOps course (beginner to advanced)."}
