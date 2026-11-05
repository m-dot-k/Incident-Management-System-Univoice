# UNIvoice — сервер

REST API на FastAPI с базой SQLite.

## Запуск

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- `--host 0.0.0.0` нужен, чтобы к серверу можно было подключиться с телефона в той же сети.
  Для работы только на своём компьютере достаточно `--host 127.0.0.1`.
- Для разработки удобно добавить `--reload`: сервер перезапускается при изменении кода.
- Интерактивная документация: http://127.0.0.1:8000/docs

## Данные

База `univoice.db` и загруженные фото хранятся в `backend/data/`. Папка создаётся сама и не попадает в git.

| Переменная окружения | Назначение |
|---|---|
| `UNIVOICE_DATA_DIR` | Другая папка для базы и фото |
| `UNIVOICE_DEMO_PASSWORD` | Пароль демо-пользователей `student`, `employee`, `admin` при создании базы. Без неё пароль генерируется случайно и печатается в консоль |

## Тесты

```bash
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -m pytest
```

Тесты работают на временной базе и не трогают `backend/data/`.

## Устройство

| Файл | Что внутри |
|---|---|
| `app/main.py` | Эндпоинты, модели запросов, проверка токена и прав ролей |
| `app/database.py` | Подключение к SQLite, миграции, хеширование паролей и токенов, демо-данные |
| `app/schema.sql` | Схема базы данных |

Описание всех эндпоинтов — в [docs/api.md](../docs/api.md).
