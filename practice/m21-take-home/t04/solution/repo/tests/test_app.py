from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_counts_courses():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["courses"] == 5


def test_search_finds_devops():
    r = client.get("/search", params={"q": "Docker basics"})
    assert r.json()["results"] == ["DevOps"]


def test_search_without_match_is_empty():
    assert client.get("/search", params={"q": "cooking"}).json()["results"] == []
