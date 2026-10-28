"""Both paths of every flag, with OpenFeature's in-memory provider (no flagd needed in tests)."""
from fastapi.testclient import TestClient
from openfeature import api
from openfeature.provider.in_memory_provider import InMemoryFlag, InMemoryProvider

import app.main as main

client = TestClient(main.app)
ON_OFF = {"on": True, "off": False}


def use_flags(**flags):
    api.set_provider(InMemoryProvider(
        {k.replace("_", "-"): InMemoryFlag("on" if v else "off", ON_OFF) for k, v in flags.items()}))


def test_ask_uses_the_model_when_on(monkeypatch):
    use_flags(copilot_answers=True)
    monkeypatch.setattr(main, "ask_model", lambda q: "model answer")
    assert client.get("/ask", params={"q": "docker"}).json()["source"] == "ai"


def test_ask_falls_back_when_off():
    use_flags(copilot_answers=False)
    body = client.get("/ask", params={"q": "docker"}).json()
    assert body["source"] == "fallback"
    assert body["answer"] == "Try the DevOps course."


def test_notes_v2_when_on():
    use_flags(lesson_notes_v2=True)
    assert client.get("/lessons/7/notes", params={"user": "u0001"}).json()["notes"] == "v2"


def test_notes_v1_when_off():
    use_flags(lesson_notes_v2=False)
    assert client.get("/lessons/7/notes", params={"user": "u0001"}).json()["notes"] == "v1"


def test_code_defaults_when_flags_are_missing(monkeypatch):
    use_flags()
    monkeypatch.setattr(main, "ask_model", lambda q: "model answer")
    assert client.get("/ask", params={"q": "docker"}).json()["source"] == "ai"
    assert client.get("/lessons/7/notes", params={"user": "u0001"}).json()["notes"] == "v1"
