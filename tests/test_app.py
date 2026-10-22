import pytest

from app import create_app


@pytest.fixture(autouse=True)
def isolated_environment(monkeypatch):
    for name in ("APP_READY", "APP_VERSION", "APP_ENV"):
        monkeypatch.delenv(name, raising=False)


def test_health_endpoint_returns_success():
    response = create_app().test_client().get("/healthz")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_application_is_ready_by_default():
    response = create_app().test_client().get("/readyz")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ready"}


def test_unready_application_remains_alive(monkeypatch):
    monkeypatch.setenv("APP_READY", "false")
    client = create_app().test_client()
    readiness = client.get("/readyz")
    assert readiness.status_code == 503
    assert readiness.get_json() == {"status": "not_ready"}
    assert client.get("/healthz").status_code == 200


def test_version_reports_deployment_configuration(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    monkeypatch.setenv("APP_ENV", "staging")
    response = create_app().test_client().get("/version")
    assert response.status_code == 200
    assert response.get_json() == {"version": "1.2.3", "environment": "staging"}


@pytest.mark.parametrize("value", ["yes", "1", "", " yes "])
def test_invalid_readiness_configuration_fails_at_startup(monkeypatch, value):
    monkeypatch.setenv("APP_READY", value)
    with pytest.raises(ValueError, match="APP_READY must be true or false"):
        create_app()


@pytest.mark.parametrize(
    "value,status,body",
    [
        (" true ", 200, {"status": "ready"}),
        ("TRUE", 200, {"status": "ready"}),
        (" False ", 503, {"status": "not_ready"}),
        ("FaLsE", 503, {"status": "not_ready"}),
    ],
)
def test_readiness_configuration_normalization(monkeypatch, value, status, body):
    monkeypatch.setenv("APP_READY", value)
    response = create_app().test_client().get("/readyz")
    assert response.status_code == status
    assert response.get_json() == body


def test_application_instances_have_separate_configuration(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "1.0.0")
    first = create_app().test_client()
    monkeypatch.setenv("APP_VERSION", "1.0.1")
    second = create_app().test_client()
    assert first.get("/version").get_json()["version"] == "1.0.0"
    assert second.get("/version").get_json()["version"] == "1.0.1"
