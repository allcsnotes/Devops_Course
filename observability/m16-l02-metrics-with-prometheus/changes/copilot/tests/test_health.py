from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_reports_courses():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["courses"] == 5


def test_ask_finds_devops():
    r = client.get("/ask", params={"q": "docker"})
    assert r.json() == {"answer": "Try the DevOps course."}


def test_metrics_count_requests():
    client.get("/health")
    text = client.get("/metrics").text
    assert 'copilot_requests_total{code="200",route="/health"}' in text
    assert "copilot_request_duration_seconds_bucket" in text
