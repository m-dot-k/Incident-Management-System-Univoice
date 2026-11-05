import os
import tempfile

import pytest

# Тесты работают на отдельной временной базе, а не на backend/data.
# Переменные нужно задать до импорта приложения.
os.environ["UNIVOICE_DATA_DIR"] = tempfile.mkdtemp(prefix="univoice-test-")
os.environ["UNIVOICE_DEMO_PASSWORD"] = "test-password-123"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

DEMO_PASSWORD = os.environ["UNIVOICE_DEMO_PASSWORD"]
# Минимальный JPEG: сервер проверяет только сигнатуру файла
JPEG = b"\xff\xd8\xff\xe0test-jpeg"


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


def login(client, username: str) -> dict:
    r = client.post("/auth/login", json={"login": username, "password": DEMO_PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture
def student(client):
    return login(client, "student")


@pytest.fixture
def employee(client):
    return login(client, "employee")


@pytest.fixture
def admin(client):
    return login(client, "admin")
