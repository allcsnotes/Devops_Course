from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_version_says_which_build():
    r = client.get("/version")
    fields = {"version", "revision", "environment", "colour", "copilot", "storefront"}
    assert set(r.json()) == fields
    assert r.headers["X-App-Version"] == r.json()["version"]
