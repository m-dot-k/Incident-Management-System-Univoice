from conftest import JPEG


def create_incident(client, student) -> int:
    r = client.post(
        "/incidents",
        headers=student,
        json={
            "type": "Жалоба",
            "category": "оборудование",
            "title": "Сломан проектор",
            "description": "Проектор в аудитории 101 не включается",
        },
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_requests_without_token_are_rejected(client):
    assert client.get("/incidents").status_code == 401
    # Старый способ «представиться» чужим id больше не работает
    assert client.get("/incidents?viewer_id=3").status_code == 401


def test_only_students_create_incidents(client, admin):
    r = client.post(
        "/incidents",
        headers=admin,
        json={"type": "Жалоба", "category": "оборудование", "title": "aaaaa", "description": "a" * 25},
    )
    assert r.status_code == 403


def test_photo_upload_checks_content_type(client, student):
    incident_id = create_incident(client, student)
    url = f"/incidents/{incident_id}/attachments"
    bad = client.post(url, headers=student, files={"file": ("p.jpg", JPEG, "application/octet-stream")})
    assert bad.status_code == 400
    good = client.post(url, headers=student, files={"file": ("p.jpg", JPEG, "image/jpeg")})
    assert good.status_code == 201
    # Фото доступно только с токеном
    assert client.get(good.json()["url"]).status_code == 401
    assert client.get(good.json()["url"], headers=student).status_code == 200


def test_employees_list_is_admin_only(client, admin, student):
    assert client.get("/employees", headers=admin).status_code == 200
    assert client.get("/employees", headers=student).status_code == 403


def test_full_incident_lifecycle_respects_roles(client, student, employee, admin):
    incident_id = create_incident(client, student)
    status_url = f"/incidents/{incident_id}/status"
    employee_id = client.get("/employees", headers=admin).json()[0]["id"]
    assign = {"status": "Назначено", "assigned_employee_id": employee_id}

    assert client.patch(status_url, headers=student, json=assign).status_code == 403
    assert client.patch(status_url, headers=admin, json=assign).status_code == 200

    assert client.patch(status_url, headers=student, json={"status": "В работе"}).status_code == 403
    assert client.patch(status_url, headers=employee, json={"status": "В работе"}).status_code == 200

    report = client.post(
        f"/incidents/{incident_id}/response",
        headers=employee,
        data={"comment": "Готово"},
        files={"after_photo": ("after.jpg", JPEG, "image/jpeg")},
    )
    assert report.status_code == 200
    assert report.json()["status"] == "Решено"

    assert client.patch(status_url, headers=employee, json={"status": "Закрыто"}).status_code == 403
    closed = client.patch(status_url, headers=student, json={"status": "Закрыто"})
    assert closed.status_code == 200
    assert closed.json()["status"] == "Закрыто"


def test_admin_hides_incident_with_reason(client, student, admin):
    incident_id = create_incident(client, student)
    r = client.request(
        "DELETE", f"/admin/incidents/{incident_id}", headers=admin, json={"reason": "Тестовое обращение"}
    )
    assert r.status_code == 200
    assert client.get(f"/incidents/{incident_id}", headers=admin).status_code == 404


def test_logout_revokes_token(client):
    from conftest import login

    headers = login(client, "student")
    assert client.post("/auth/logout", headers=headers).status_code == 200
    assert client.get("/incidents", headers=headers).status_code == 401