

def test_health_reports_version():
    assert client.get("/health").json()["version"] == "dev"
