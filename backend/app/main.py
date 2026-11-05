from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from sqlite3 import IntegrityError
from typing import Annotated, Literal
from uuid import uuid4

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field
from fastapi.middleware.cors import CORSMiddleware

from .database import (
    UPLOAD_DIR,
    get_connection,
    hash_password,
    hash_token,
    init_db,
    new_token,
    utc_now,
    verify_password,
)

SESSION_LIFETIME = timedelta(days=30)


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    yield


app = FastAPI(title="UNIvoice API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    # Авторизация идёт через заголовок Authorization, cookies не нужны
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

MAX_ATTACHMENT_SIZE = 5 * 1024 * 1024
MAX_ATTACHMENTS_PER_INCIDENT = 5
ALLOWED_IMAGE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png"}

ALLOWED_TRANSITIONS = {
    "Новое": ["Назначено"],
    "Назначено": ["В работе"],
    "В работе": ["Решено"],
    "Решено": ["Закрыто", "Новое"],
    "Закрыто": [],
}


class RequestModel(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)


class RegisterRequest(RequestModel):
    login: str = Field(
        min_length=3,
        max_length=30,
        pattern=r"^[A-Za-z0-9_.-]+$",
    )
    display_name: str = Field(min_length=2, max_length=100)
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(RequestModel):
    login: str = Field(min_length=3, max_length=30)
    password: str = Field(min_length=8, max_length=128)


class IncidentCreate(RequestModel):
    type: Literal["Жалоба", "Предложение"]
    category: str = Field(min_length=1)
    title: str = Field(min_length=5, max_length=100)
    description: str = Field(min_length=20, max_length=2000)


class StatusUpdate(RequestModel):
    status: Literal["Новое", "Назначено", "В работе", "Решено", "Закрыто"]
    reason: str | None = None
    assigned_employee_id: int | None = None


class AdminDeleteRequest(RequestModel):
    reason: str = Field(min_length=5, max_length=500)


def get_current_user(authorization: str | None = Header(None)) -> dict:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Требуется вход в систему")
    connection = get_connection()
    try:
        user = connection.execute(
            """
            SELECT u.id, u.role, u.display_name
            FROM sessions AS s
            JOIN users AS u ON u.id = s.user_id
            WHERE s.token_hash = ? AND s.expires_at > ? AND u.is_active = 1
            """,
            (hash_token(token.strip()), utc_now()),
        ).fetchone()
    finally:
        connection.close()
    if user is None:
        raise HTTPException(status_code=401, detail="Сессия истекла, войдите снова")
    return dict(user)


CurrentUser = Annotated[dict, Depends(get_current_user)]


def require_role(user: dict, role: str, error: str) -> None:
    if user["role"] != role:
        raise HTTPException(status_code=403, detail=error)


def can_change_status(current_status: str, new_status: str) -> bool:
    return new_status in ALLOWED_TRANSITIONS.get(current_status, [])


def has_valid_image_signature(content: bytes, mime_type: str) -> bool:
    if mime_type == "image/png":
        return content.startswith(b"\x89PNG\r\n\x1a\n")
    if mime_type == "image/jpeg":
        return content.startswith(b"\xff\xd8\xff")
    return False


def find_incident(connection, incident_id: int, include_deleted: bool = False):
    query = "SELECT * FROM incidents WHERE id = ?"
    if not include_deleted:
        query += " AND deleted_at IS NULL"
    return connection.execute(query, (incident_id,)).fetchone()


def can_view_incident(viewer, incident) -> bool:
    if viewer["role"] == "admin":
        return True
    if viewer["role"] == "student":
        return incident["student_id"] == viewer["id"]
    if viewer["role"] == "employee":
        return (
            incident["type"] == "Жалоба"
            and incident["assigned_employee_id"] == viewer["id"]
        )
    return False


def incident_to_dict(
    connection, incident_id: int, include_deleted: bool = False
) -> dict:
    row = connection.execute(
        """
        SELECT
            i.*,
            c.name AS category,
            student.display_name AS student_name,
            employee.display_name AS assigned_employee_name,
            (
                SELECT r.text
                FROM responses AS r
                WHERE r.incident_id = i.id
                  AND r.round_number = i.current_round
            ) AS response
        FROM incidents AS i
        JOIN categories AS c ON c.id = i.category_id
        JOIN users AS student ON student.id = i.student_id
        LEFT JOIN users AS employee ON employee.id = i.assigned_employee_id
        WHERE i.id = ?
        """,
        (incident_id,),
    ).fetchone()

    if row is None or (row["deleted_at"] is not None and not include_deleted):
        raise HTTPException(status_code=404, detail="Обращение не найдено")

    result = dict(row)
    attachments = connection.execute(
        """
        SELECT id, mime_type, size_bytes, created_at
        FROM attachments
        WHERE incident_id = ?
        ORDER BY id
        """,
        (incident_id,),
    ).fetchall()
    result["attachments"] = [
        {
            **dict(attachment),
            "url": f"/attachments/{attachment['id']}",
        }
        for attachment in attachments
    ]

    response = connection.execute(
        """
        SELECT id, text, published_at
        FROM responses
        WHERE incident_id = ? AND round_number = ?
        """,
        (incident_id, row["current_round"]),
    ).fetchone()
    if response is None:
        result["response_report"] = None
    else:
        report_photos = connection.execute(
            """
            SELECT id, kind, mime_type, size_bytes, created_at
            FROM response_attachments
            WHERE response_id = ?
            ORDER BY CASE kind WHEN 'before' THEN 1 ELSE 2 END
            """,
            (response["id"],),
        ).fetchall()
        report_photo_items = [
            {
                **dict(photo),
                "source": "employee",
                "url": f"/response-attachments/{photo['id']}",
            }
            for photo in report_photos
        ]
        if not any(photo["kind"] == "before" for photo in report_photo_items):
            student_before = attachments[0] if attachments else None
            if student_before is not None:
                report_photo_items.insert(
                    0,
                    {
                        **dict(student_before),
                        "kind": "before",
                        "source": "student",
                        "url": f"/attachments/{student_before['id']}",
                    },
                )
        result["response_report"] = {
            "id": response["id"],
            "comment": response["text"] or None,
            "published_at": response["published_at"],
            "photos": report_photo_items,
        }
    return result


@app.get("/", summary="Проверить работу сервера")
def home():
    return {
        "message": "UNIvoice backend works",
        "database": "SQLite подключена",
    }


@app.post(
    "/auth/register",
    status_code=201,
    summary="Зарегистрировать студента по логину",
)
def register(data: RegisterRequest):
    connection = get_connection()
    try:
        login = data.login.casefold()
        email = data.email.casefold()
        now = utc_now()
        try:
            cursor = connection.execute(
                """
                INSERT INTO users (
                    username, display_name, email, password_hash, role,
                    is_active, must_change_password, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, 'student', 1, 0, ?, ?)
                """,
                (
                    login,
                    data.display_name,
                    email,
                    hash_password(data.password),
                    now,
                    now,
                ),
            )
            connection.commit()
        except IntegrityError:
            connection.rollback()
            raise HTTPException(
                status_code=409,
                detail="Логин или email уже используется",
            )
        return {
            "id": cursor.lastrowid,
            "login": login,
            "display_name": data.display_name,
            "email": email,
            "role": "student",
        }
    finally:
        connection.close()


@app.post("/auth/login", summary="Войти по логину и паролю")
def login(data: LoginRequest):
    connection = get_connection()
    try:
        user = connection.execute(
            """
            SELECT id, username, display_name, email, password_hash, role
            FROM users
            WHERE username = ? COLLATE NOCASE AND is_active = 1
            """,
            (data.login,),
        ).fetchone()
        if user is None or not verify_password(
            data.password, user["password_hash"]
        ):
            raise HTTPException(
                status_code=401,
                detail="Неверный логин или пароль",
            )
        token = new_token()
        now = datetime.now(timezone.utc)
        connection.execute(
            """
            INSERT INTO sessions (token_hash, user_id, created_at, expires_at)
            VALUES (?, ?, ?, ?)
            """,
            (
                hash_token(token),
                user["id"],
                now.isoformat(),
                (now + SESSION_LIFETIME).isoformat(),
            ),
        )
        connection.commit()
        return {
            "message": "Вход выполнен",
            "access_token": token,
            "token_type": "bearer",
            "user": {
                "id": user["id"],
                "login": user["username"],
                "display_name": user["display_name"],
                "email": user["email"],
                "role": user["role"],
            },
        }
    finally:
        connection.close()


@app.post("/auth/logout", summary="Выйти из системы")
def logout(authorization: str | None = Header(None)):
    _, _, token = (authorization or "").partition(" ")
    if token.strip():
        connection = get_connection()
        try:
            connection.execute(
                "DELETE FROM sessions WHERE token_hash = ?",
                (hash_token(token.strip()),),
            )
            connection.commit()
        finally:
            connection.close()
    return {"message": "Выход выполнен"}


@app.get("/employees", summary="Список активных сотрудников")
def get_employees(viewer: CurrentUser):
    require_role(viewer, "admin", "Список сотрудников доступен только администратору")
    connection = get_connection()
    try:
        rows = connection.execute(
            """
            SELECT id, display_name, email FROM users
            WHERE role = 'employee' AND is_active = 1
            ORDER BY display_name
            """
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        connection.close()


@app.get(
    "/incidents",
    summary="Получить доступные пользователю обращения",
)
def get_incidents(viewer: CurrentUser):
    viewer_id = viewer["id"]
    connection = get_connection()
    try:
        if viewer["role"] == "student":
            ids = connection.execute(
                """
                SELECT id FROM incidents
                WHERE deleted_at IS NULL AND student_id = ?
                ORDER BY created_at DESC, id DESC
                """,
                (viewer_id,),
            ).fetchall()
        elif viewer["role"] == "employee":
            ids = connection.execute(
                """
                SELECT id FROM incidents
                WHERE deleted_at IS NULL
                  AND assigned_employee_id = ?
                  AND type = 'Жалоба'
                ORDER BY created_at DESC, id DESC
                """,
                (viewer_id,),
            ).fetchall()
        else:
            ids = connection.execute(
                """
                SELECT id FROM incidents
                WHERE deleted_at IS NULL
                ORDER BY created_at DESC, id DESC
                """
            ).fetchall()
        return [incident_to_dict(connection, row["id"]) for row in ids]
    finally:
        connection.close()


@app.post(
    "/incidents",
    status_code=201,
    summary="Создать жалобу или предложение",
)
def create_incident(data: IncidentCreate, viewer: CurrentUser):
    require_role(viewer, "student", "Создавать обращения могут только студенты")
    student_id = viewer["id"]
    connection = get_connection()
    try:
        category = connection.execute(
            """
            SELECT id FROM categories
            WHERE name_key = ? AND is_active = 1
            """,
            (data.category.strip().casefold(),),
        ).fetchone()
        if category is None:
            raise HTTPException(status_code=400, detail="Категория не найдена")

        now = utc_now()
        cursor = connection.execute(
            """
            INSERT INTO incidents (
                student_id, type, category_id, title, description,
                status, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, 'Новое', ?, ?)
            """,
            (
                student_id,
                data.type,
                category["id"],
                data.title.strip(),
                data.description.strip(),
                now,
                now,
            ),
        )
        incident_id = cursor.lastrowid
        connection.execute(
            """
            INSERT INTO status_history (
                incident_id, round_number, old_status, new_status,
                changed_by_user_id, created_at
            )
            VALUES (?, 1, NULL, 'Новое', ?, ?)
            """,
            (incident_id, student_id, now),
        )
        connection.commit()
        return incident_to_dict(connection, incident_id)
    finally:
        connection.close()


@app.post(
    "/incidents/{incident_id}/attachments",
    status_code=201,
    summary="Добавить фотографию к обращению",
)
async def add_attachment(
    incident_id: int,
    viewer: CurrentUser,
    file: UploadFile = File(...),
):
    connection = get_connection()
    saved_path = None
    try:
        incident = find_incident(connection, incident_id)
        if incident is None:
            raise HTTPException(status_code=404, detail="Обращение не найдено")
        if viewer["role"] != "student" or incident["student_id"] != viewer["id"]:
            raise HTTPException(
                status_code=403,
                detail="Добавлять фото может только автор обращения",
            )
        if incident["status"] != "Новое":
            raise HTTPException(
                status_code=400,
                detail="Фото можно добавить только к новому обращению",
            )
        if file.content_type not in ALLOWED_IMAGE_TYPES:
            raise HTTPException(
                status_code=400,
                detail="Разрешены только изображения JPEG и PNG",
            )

        attachment_count = connection.execute(
            "SELECT COUNT(*) FROM attachments WHERE incident_id = ?",
            (incident_id,),
        ).fetchone()[0]
        if attachment_count >= MAX_ATTACHMENTS_PER_INCIDENT:
            raise HTTPException(
                status_code=400,
                detail="К обращению можно добавить не больше 5 фотографий",
            )

        content = await file.read(MAX_ATTACHMENT_SIZE + 1)
        if not content:
            raise HTTPException(status_code=400, detail="Файл пустой")
        if len(content) > MAX_ATTACHMENT_SIZE:
            raise HTTPException(
                status_code=400,
                detail="Размер фотографии не должен превышать 5 МБ",
            )
        if not has_valid_image_signature(content, file.content_type):
            raise HTTPException(
                status_code=400,
                detail="Содержимое файла не соответствует формату изображения",
            )

        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        storage_key = f"{uuid4().hex}{ALLOWED_IMAGE_TYPES[file.content_type]}"
        saved_path = UPLOAD_DIR / storage_key
        saved_path.write_bytes(content)
        now = utc_now()
        cursor = connection.execute(
            """
            INSERT INTO attachments (
                incident_id, storage_key, mime_type, size_bytes, created_at
            )
            VALUES (?, ?, ?, ?, ?)
            """,
            (incident_id, storage_key, file.content_type, len(content), now),
        )
        connection.commit()
        return {
            "id": cursor.lastrowid,
            "incident_id": incident_id,
            "mime_type": file.content_type,
            "size_bytes": len(content),
            "created_at": now,
            "url": f"/attachments/{cursor.lastrowid}",
        }
    except Exception:
        if saved_path is not None and saved_path.exists():
            saved_path.unlink()
        raise
    finally:
        await file.close()
        connection.close()


@app.get(
    "/attachments/{attachment_id}",
    summary="Получить фотографию обращения",
    response_class=FileResponse,
)
def get_attachment(attachment_id: int, viewer: CurrentUser):
    connection = get_connection()
    try:
        attachment = connection.execute(
            """
            SELECT a.*, i.student_id, i.assigned_employee_id, i.type
            FROM attachments AS a
            JOIN incidents AS i ON i.id = a.incident_id
            WHERE a.id = ? AND i.deleted_at IS NULL
            """,
            (attachment_id,),
        ).fetchone()
        if attachment is None:
            raise HTTPException(status_code=404, detail="Фотография не найдена")
        if not can_view_incident(viewer, attachment):
            raise HTTPException(status_code=403, detail="Нет доступа к фотографии")
        path = UPLOAD_DIR / attachment["storage_key"]
        if not path.is_file():
            raise HTTPException(status_code=404, detail="Файл фотографии не найден")
        return FileResponse(path, media_type=attachment["mime_type"])
    finally:
        connection.close()


@app.get(
    "/response-attachments/{attachment_id}",
    summary="Получить фотографию отчёта сотрудника",
    response_class=FileResponse,
)
def get_response_attachment(attachment_id: int, viewer: CurrentUser):
    connection = get_connection()
    try:
        attachment = connection.execute(
            """
            SELECT
                ra.*,
                i.student_id,
                i.assigned_employee_id,
                i.type,
                i.deleted_at
            FROM response_attachments AS ra
            JOIN responses AS r ON r.id = ra.response_id
            JOIN incidents AS i ON i.id = r.incident_id
            WHERE ra.id = ? AND i.deleted_at IS NULL
            """,
            (attachment_id,),
        ).fetchone()
        if attachment is None:
            raise HTTPException(
                status_code=404,
                detail="Фотография отчёта не найдена",
            )
        if not can_view_incident(viewer, attachment):
            raise HTTPException(
                status_code=403,
                detail="Нет доступа к фотографии отчёта",
            )
        path = UPLOAD_DIR / attachment["storage_key"]
        if not path.is_file():
            raise HTTPException(
                status_code=404,
                detail="Файл фотографии отчёта не найден",
            )
        return FileResponse(path, media_type=attachment["mime_type"])
    finally:
        connection.close()


@app.get("/incidents/{incident_id}", summary="Получить обращение по номеру")
def get_incident(incident_id: int, viewer: CurrentUser):
    connection = get_connection()
    try:
        incident = find_incident(connection, incident_id)
        if incident is None:
            raise HTTPException(status_code=404, detail="Обращение не найдено")
        if not can_view_incident(viewer, incident):
            raise HTTPException(status_code=403, detail="Нет доступа к обращению")
        return incident_to_dict(connection, incident_id)
    finally:
        connection.close()


@app.delete(
    "/incidents/{incident_id}",
    summary="Отменить своё новое обращение",
)
def cancel_incident(incident_id: int, viewer: CurrentUser):
    student_id = viewer["id"]
    connection = get_connection()
    try:
        incident = find_incident(connection, incident_id)
        if incident is None:
            raise HTTPException(status_code=404, detail="Обращение не найдено")
        if viewer["role"] != "student" or incident["student_id"] != student_id:
            raise HTTPException(
                status_code=403,
                detail="Отменить обращение может только его автор",
            )
        if incident["status"] != "Новое":
            raise HTTPException(
                status_code=400,
                detail="Отменить можно только новое обращение",
            )
        now = utc_now()
        connection.execute(
            """
            UPDATE incidents
            SET deleted_at = ?, deleted_by_user_id = ?,
                deletion_reason = ?, deletion_kind = 'student_cancelled',
                version = version + 1, updated_at = ?
            WHERE id = ?
            """,
            (now, student_id, "Отменено студентом", now, incident_id),
        )
        connection.commit()
        return {
            "message": "Обращение отменено",
            "incident_id": incident_id,
            "deleted_at": now,
        }
    finally:
        connection.close()


@app.delete(
    "/admin/incidents/{incident_id}",
    summary="Скрыть обращение при модерации",
)
def moderate_incident(
    incident_id: int, data: AdminDeleteRequest, viewer: CurrentUser
):
    require_role(viewer, "admin", "Скрывать обращения может только администратор")
    connection = get_connection()
    try:
        incident = find_incident(connection, incident_id)
        if incident is None:
            raise HTTPException(status_code=404, detail="Обращение не найдено")
        now = utc_now()
        connection.execute(
            """
            UPDATE incidents
            SET deleted_at = ?, deleted_by_user_id = ?,
                deletion_reason = ?, deletion_kind = 'admin_removed',
                version = version + 1, updated_at = ?
            WHERE id = ?
            """,
            (now, viewer["id"], data.reason, now, incident_id),
        )
        connection.commit()
        return {
            "message": "Обращение скрыто администратором",
            "incident_id": incident_id,
            "reason": data.reason,
            "deleted_at": now,
        }
    finally:
        connection.close()


@app.patch("/incidents/{incident_id}/status", summary="Изменить статус обращения")
def change_status(incident_id: int, data: StatusUpdate, viewer: CurrentUser):
    connection = get_connection()
    try:
        incident = find_incident(connection, incident_id)
        if incident is None:
            raise HTTPException(status_code=404, detail="Обращение не найдено")

        # Кто какой переход может делать
        if data.status == "Назначено":
            require_role(viewer, "admin", "Назначать сотрудника может только администратор")
        elif data.status == "В работе":
            if (
                viewer["role"] != "employee"
                or incident["assigned_employee_id"] != viewer["id"]
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Взять в работу может только назначенный сотрудник",
                )
        elif data.status in {"Новое", "Закрыто"}:
            if viewer["role"] != "student" or incident["student_id"] != viewer["id"]:
                raise HTTPException(
                    status_code=403,
                    detail="Принять или вернуть обращение может только его автор",
                )

        if data.status == "Решено":
            raise HTTPException(
                status_code=400,
                detail="Для статуса «Решено» сначала опубликуй ответ",
            )

        if not can_change_status(incident["status"], data.status):
            raise HTTPException(status_code=400, detail="Недопустимый переход статуса")

        now = utc_now()
        assigned_employee_id = incident["assigned_employee_id"]
        current_round = incident["current_round"]
        closed_at = incident["closed_at"]
        reason = None

        if data.status == "Назначено":
            if incident["type"] != "Жалоба":
                raise HTTPException(
                    status_code=400,
                    detail="Предложения сотрудникам не назначаются",
                )
            employee = connection.execute(
                """
                SELECT id FROM users
                WHERE id = ? AND role = 'employee' AND is_active = 1
                """,
                (data.assigned_employee_id,),
            ).fetchone()
            if employee is None:
                raise HTTPException(status_code=400, detail="Сотрудник не найден")
            assigned_employee_id = employee["id"]

        if data.status == "В работе" and assigned_employee_id is None:
            raise HTTPException(status_code=400, detail="Сначала назначь сотрудника")

        if incident["status"] == "Решено" and data.status == "Новое":
            if not data.reason or not data.reason.strip():
                raise HTTPException(
                    status_code=400,
                    detail="Укажи причину повторного открытия",
                )
            reason = data.reason.strip()
            current_round += 1
            assigned_employee_id = None
            closed_at = None

        if data.status == "Закрыто":
            closed_at = now

        connection.execute(
            """
            UPDATE incidents
            SET status = ?, assigned_employee_id = ?, current_round = ?,
                version = version + 1, updated_at = ?, closed_at = ?
            WHERE id = ?
            """,
            (
                data.status,
                assigned_employee_id,
                current_round,
                now,
                closed_at,
                incident_id,
            ),
        )

        changed_by_user_id = viewer["id"]

        connection.execute(
            """
            INSERT INTO status_history (
                incident_id, round_number, old_status, new_status,
                changed_by_user_id, assigned_employee_id, reason, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                incident_id,
                current_round,
                incident["status"],
                data.status,
                changed_by_user_id,
                assigned_employee_id,
                reason,
                now,
            ),
        )
        connection.commit()
        return incident_to_dict(connection, incident_id)
    finally:
        connection.close()


@app.post(
    "/incidents/{incident_id}/response",
    summary="Завершить работу: фото «после» обязательно, «до» необязательно",
)
async def create_response(
    incident_id: int,
    viewer: CurrentUser,
    comment: str | None = Form(None, max_length=2000),
    before_photo: UploadFile | None = File(None),
    after_photo: UploadFile = File(...),
):
    employee_id = viewer["id"]
    connection = get_connection()
    saved_paths: list[Path] = []
    try:
        incident = find_incident(connection, incident_id)
        if incident is None:
            raise HTTPException(status_code=404, detail="Обращение не найдено")

        if incident["type"] != "Жалоба":
            raise HTTPException(
                status_code=400,
                detail="Фотоотчёт создаётся только для жалобы",
            )
        if incident["status"] != "В работе":
            raise HTTPException(
                status_code=400,
                detail="Отчёт можно опубликовать только для обращения в работе",
            )
        if (
            viewer["role"] != "employee"
            or incident["assigned_employee_id"] != employee_id
        ):
            raise HTTPException(
                status_code=403,
                detail="Отчёт может опубликовать только назначенный сотрудник",
            )

        uploads = [("after", after_photo)]
        if before_photo is not None:
            uploads.insert(0, ("before", before_photo))
        prepared_photos = []
        for kind, photo in uploads:
            if photo.content_type not in ALLOWED_IMAGE_TYPES:
                raise HTTPException(
                    status_code=400,
                    detail="Разрешены только изображения JPEG и PNG",
                )
            content = await photo.read(MAX_ATTACHMENT_SIZE + 1)
            if not content:
                raise HTTPException(status_code=400, detail="Файл пустой")
            if len(content) > MAX_ATTACHMENT_SIZE:
                raise HTTPException(
                    status_code=400,
                    detail="Размер каждой фотографии не должен превышать 5 МБ",
                )
            if not has_valid_image_signature(content, photo.content_type):
                raise HTTPException(
                    status_code=400,
                    detail="Содержимое файла не соответствует формату изображения",
                )
            prepared_photos.append(
                (kind, photo.content_type, content)
            )

        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        now = utc_now()
        response_text = (comment or "").strip()
        cursor = connection.execute(
            """
            INSERT INTO responses (
                incident_id, employee_id, round_number, text, published_at
            )
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                incident_id,
                employee_id,
                incident["current_round"],
                response_text,
                now,
            ),
        )
        response_id = cursor.lastrowid

        for kind, mime_type, content in prepared_photos:
            storage_key = (
                f"response_{response_id}_{kind}_{uuid4().hex}"
                f"{ALLOWED_IMAGE_TYPES[mime_type]}"
            )
            saved_path = UPLOAD_DIR / storage_key
            saved_path.write_bytes(content)
            saved_paths.append(saved_path)
            connection.execute(
                """
                INSERT INTO response_attachments (
                    response_id, kind, storage_key,
                    mime_type, size_bytes, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    response_id,
                    kind,
                    storage_key,
                    mime_type,
                    len(content),
                    now,
                ),
            )

        connection.execute(
            """
            UPDATE incidents
            SET status = 'Решено', version = version + 1, updated_at = ?
            WHERE id = ?
            """,
            (now, incident_id),
        )
        connection.execute(
            """
            INSERT INTO status_history (
                incident_id, round_number, old_status, new_status,
                changed_by_user_id, assigned_employee_id, created_at
            )
            VALUES (?, ?, 'В работе', 'Решено', ?, ?, ?)
            """,
            (
                incident_id,
                incident["current_round"],
                employee_id,
                employee_id,
                now,
            ),
        )
        connection.execute(
            """
            INSERT INTO notifications (
                user_id, incident_id, event_type, message, created_at
            )
            VALUES (?, ?, 'response_published', ?, ?)
            """,
            (
                incident["student_id"],
                incident_id,
                "Сотрудник опубликовал фотоотчёт по обращению",
                now,
            ),
        )
        connection.commit()
        return incident_to_dict(connection, incident_id)
    except Exception:
        connection.rollback()
        for saved_path in saved_paths:
            if saved_path.exists():
                saved_path.unlink()
        raise
    finally:
        if before_photo is not None:
            await before_photo.close()
        await after_photo.close()
        connection.close()
