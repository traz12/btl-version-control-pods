from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_hello_says_hello():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["message"] == "Hello World from breaker"


def test_healthz_is_ok():
    assert client.get("/healthz").json() == {"status": "ok"}


def test_version_reports_the_environment():
    body = client.get("/version").json()
    assert set(body) == {"environment", "version", "git_sha", "built_at"}
