import hashlib
import hmac
import secrets
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


DB_PATH = Path(__file__).with_name("univoice.db")
SCHEMA_PATH = Path(__file__).with_name("schema.sql")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def hash_password(password: str) -> str:
    iterations = 200_000
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        iterations,
    )
    return (
        f"pbkdf2_sha256${iterations}$"
        f"{salt.hex()}${digest.hex()}"
    )


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        algorithm, iterations_text, salt_hex, digest_hex = stored_hash.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            bytes.fromhex(salt_hex),
            int(iterations_text),
        )
        return hmac.compare_digest(digest.hex(), digest_hex)
    except (ValueError, TypeError):
        return False


def get_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def init_db() -> None:
    connection = get_connection()
    try:
        tables_exist = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'users'"
        ).fetchone()

        if not tables_exist:
            connection.executescript(SCHEMA_PATH.read_text(encoding="utf-8-sig"))

        migrate_db(connection)
        seed_demo_data(connection)
        connection.commit()
    finally:
        connection.close()


def migrate_db(connection: sqlite3.Connection) -> None:
    """Bring an existing demo database up to the current schema."""
    user_columns = {
        row["name"] for row in connection.execute("PRAGMA table_info(users)")
    }
    if "username" not in user_columns:
        connection.execute("ALTER TABLE users ADD COLUMN username TEXT")
    connection.execute(
        """
        UPDATE users
        SET username = CASE id
            WHEN 1 THEN 'student'
            WHEN 2 THEN 'employee'
            WHEN 3 THEN 'admin'
            ELSE 'user_' || id
        END
        WHERE username IS NULL OR TRIM(username) = ''
        """
    )
    connection.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_nocase
        ON users(username COLLATE NOCASE)
        """
    )
    demo_password_hash = hash_password("demo12345")
    connection.execute(
        """
        UPDATE users
        SET password_hash = ?
        WHERE password_hash = 'demo-only'
        """,
        (demo_password_hash,),
    )

    incident_columns = {
        row["name"] for row in connection.execute("PRAGMA table_info(incidents)")
    }
    new_columns = {
        "deleted_at": "TEXT",
        "deleted_by_user_id": "INTEGER REFERENCES users(id)",
        "deletion_reason": "TEXT",
        "deletion_kind": (
            "TEXT CHECK (deletion_kind IN "
            "('student_cancelled', 'admin_removed'))"
        ),
    }
    for name, definition in new_columns.items():
        if name not in incident_columns:
            connection.execute(
                f"ALTER TABLE incidents ADD COLUMN {name} {definition}"
            )
    connection.commit()

    unique_incident_index = False
    for index in connection.execute("PRAGMA index_list(attachments)"):
        if not index["unique"]:
            continue
        columns = [
            row["name"]
            for row in connection.execute(
                f"PRAGMA index_info('{index['name']}')"
            )
        ]
        if columns == ["incident_id"]:
            unique_incident_index = True
            break

    if unique_incident_index:
        connection.execute("PRAGMA foreign_keys = OFF")
        connection.executescript(
            """
            BEGIN TRANSACTION;
            ALTER TABLE attachments RENAME TO attachments_old;
            CREATE TABLE attachments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                incident_id INTEGER NOT NULL,
                storage_key TEXT NOT NULL UNIQUE,
                mime_type TEXT NOT NULL CHECK (
                    mime_type IN ('image/jpeg', 'image/png')
                ),
                size_bytes INTEGER NOT NULL CHECK (
                    size_bytes BETWEEN 1 AND 5242880
                ),
                created_at TEXT NOT NULL,
                FOREIGN KEY (incident_id) REFERENCES incidents(id)
            );
            INSERT INTO attachments (
                id, incident_id, storage_key, mime_type, size_bytes, created_at
            )
            SELECT
                id, incident_id, storage_key, mime_type, size_bytes, created_at
            FROM attachments_old;
            DROP TABLE attachments_old;
            CREATE INDEX idx_attachments_incident
                ON attachments(incident_id, id);
            COMMIT;
            """
        )
        connection.execute("PRAGMA foreign_keys = ON")
    else:
        connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_attachments_incident
            ON attachments(incident_id, id)
            """
        )

    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS response_attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            response_id INTEGER NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('before', 'after')),
            storage_key TEXT NOT NULL UNIQUE,
            mime_type TEXT NOT NULL CHECK (
                mime_type IN ('image/jpeg', 'image/png')
            ),
            size_bytes INTEGER NOT NULL CHECK (
                size_bytes BETWEEN 1 AND 5242880
            ),
            created_at TEXT NOT NULL,
            FOREIGN KEY (response_id) REFERENCES responses(id)
                ON DELETE CASCADE,
            UNIQUE (response_id, kind)
        );
        CREATE INDEX IF NOT EXISTS idx_response_attachments_response
            ON response_attachments(response_id, kind);
        """
    )


def seed_demo_data(connection: sqlite3.Connection) -> None:
    now = utc_now()
    demo_users = [
        (1, "student", "Тестовый студент", "student@demo.local", "student"),
        (2, "employee", "Тестовый сотрудник", "employee@demo.local", "employee"),
        (3, "admin", "Тестовый администратор", "admin@demo.local", "admin"),
    ]

    for user_id, username, display_name, email, role in demo_users:
        connection.execute(
            """
            INSERT OR IGNORE INTO users (
                id, username, display_name, email, password_hash, role,
                is_active, must_change_password, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, 1, 0, ?, ?)
            """,
            (
                user_id,
                username,
                display_name,
                email,
                hash_password("demo12345"),
                role,
                now,
                now,
            ),
        )

    demo_categories = [
        (1, "Оборудование", "оборудование"),
        (2, "Учебный процесс", "учебный процесс"),
        (3, "Инфраструктура", "инфраструктура"),
    ]

    for category_id, name, name_key in demo_categories:
        connection.execute(
            """
            INSERT OR IGNORE INTO categories (
                id, name, name_key, is_active, created_at
            )
            VALUES (?, ?, ?, 1, ?)
            """,
            (category_id, name, name_key, now),
        )

#.venv/bin/python -m uvicorn main:app --reload
