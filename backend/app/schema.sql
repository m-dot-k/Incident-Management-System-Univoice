PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

CREATE TABLE users (
id INTEGER PRIMARY KEY AUTOINCREMENT,
username TEXT NOT NULL COLLATE NOCASE UNIQUE,
display_name TEXT NOT NULL,
email TEXT NOT NULL UNIQUE,
password_hash TEXT NOT NULL,
role TEXT NOT NULL CHECK (role IN ('student', 'employee', 'admin')),
is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
must_change_password INTEGER NOT NULL DEFAULT 0 CHECK (must_change_password IN (0, 1)),
created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

CREATE TABLE categories (
id INTEGER PRIMARY KEY AUTOINCREMENT,
name TEXT NOT NULL,
name_key TEXT NOT NULL UNIQUE,
is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
created_at TEXT NOT NULL
);

CREATE TABLE incidents (
id INTEGER PRIMARY KEY AUTOINCREMENT,
student_id INTEGER NOT NULL,
type TEXT NOT NULL CHECK (type IN ('Жалоба', 'Предложение')),
category_id INTEGER NOT NULL,
title TEXT NOT NULL,
description TEXT NOT NULL,
status TEXT NOT NULL DEFAULT 'Новое' CHECK (status IN ('Новое', 'Назначено', 'В работе', 'Решено', 'Закрыто')),
assigned_employee_id INTEGER,
current_round INTEGER NOT NULL DEFAULT 1 CHECK (current_round >= 1),
version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
created_at TEXT NOT NULL,
updated_at TEXT NOT NULL,
closed_at TEXT,
deleted_at TEXT,
deleted_by_user_id INTEGER,
deletion_reason TEXT,
deletion_kind TEXT CHECK (deletion_kind IN ('student_cancelled', 'admin_removed')),
FOREIGN KEY (student_id) REFERENCES users(id),
FOREIGN KEY (category_id) REFERENCES categories(id),
FOREIGN KEY (assigned_employee_id) REFERENCES users(id),
FOREIGN KEY (deleted_by_user_id) REFERENCES users(id)
);

CREATE TABLE attachments (
id INTEGER PRIMARY KEY AUTOINCREMENT,
incident_id INTEGER NOT NULL,
storage_key TEXT NOT NULL UNIQUE,
mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
size_bytes INTEGER NOT NULL CHECK (size_bytes BETWEEN 1 AND 5242880),
created_at TEXT NOT NULL,
FOREIGN KEY (incident_id) REFERENCES incidents(id)
);

CREATE TABLE responses (
id INTEGER PRIMARY KEY AUTOINCREMENT,
incident_id INTEGER NOT NULL,
employee_id INTEGER NOT NULL,
round_number INTEGER NOT NULL CHECK (round_number >= 1),
text TEXT NOT NULL,
published_at TEXT NOT NULL,
FOREIGN KEY (incident_id) REFERENCES incidents(id),
FOREIGN KEY (employee_id) REFERENCES users(id),

UNIQUE (incident_id, round_number)
);

CREATE TABLE response_attachments (
id INTEGER PRIMARY KEY AUTOINCREMENT,
response_id INTEGER NOT NULL,
kind TEXT NOT NULL CHECK (kind IN ('before', 'after')),
storage_key TEXT NOT NULL UNIQUE,
mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
size_bytes INTEGER NOT NULL CHECK (size_bytes BETWEEN 1 AND 5242880),
created_at TEXT NOT NULL,
FOREIGN KEY (response_id) REFERENCES responses(id) ON DELETE CASCADE,
UNIQUE (response_id, kind)
);

CREATE TABLE status_history (
id INTEGER PRIMARY KEY AUTOINCREMENT,
incident_id INTEGER NOT NULL,
round_number INTEGER NOT NULL CHECK (round_number >= 1),
old_status TEXT,
new_status TEXT NOT NULL CHECK (new_status IN ('Новое', 'Назначено', 'В работе', 'Решено', 'Закрыто')),
changed_by_user_id INTEGER NOT NULL,
assigned_employee_id INTEGER,
reason TEXT, created_at TEXT NOT NULL,
FOREIGN KEY (incident_id) REFERENCES incidents(id),
FOREIGN KEY (changed_by_user_id) REFERENCES users(id),
FOREIGN KEY (assigned_employee_id) REFERENCES users(id)
);

CREATE TABLE notifications (
id INTEGER PRIMARY KEY AUTOINCREMENT,
user_id INTEGER NOT NULL,
incident_id INTEGER NOT NULL,
event_type TEXT NOT NULL CHECK (event_type IN ('status_changed', 'response_published')),
message TEXT NOT NULL,
is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0, 1)),
created_at TEXT NOT NULL,
FOREIGN KEY (user_id) REFERENCES users(id),
FOREIGN KEY (incident_id) REFERENCES incidents(id)
);

CREATE INDEX idx_incidents_student_created ON incidents(student_id, created_at, id);
CREATE INDEX idx_incidents_employee_status ON incidents(assigned_employee_id, status);
CREATE INDEX idx_incidents_category_created ON incidents(category_id, created_at);
CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_attachments_incident ON attachments(incident_id, id);
CREATE INDEX idx_response_attachments_response ON response_attachments(response_id, kind);
CREATE INDEX idx_status_history_incident_created ON status_history(incident_id, created_at, id);
CREATE INDEX idx_notifications_user_read_created ON notifications(user_id, is_read, created_at);
COMMIT;
