from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_ask_ignores_case():
    r = client.get("/ask", params={"q": "Kubernetes"})
    assert r.json() == {"answer": "Try the DevOps course."}
