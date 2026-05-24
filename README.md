# BI Admin

An internal admin console with a Flutter Web frontend and a FastAPI backend.

## Features

- JWT authentication with 15-minute inactivity auto-logout
- Super admin and user roles; super admin creates and approves accounts
- SFTP file browser (browse, upload, download, delete, archive to zip)
- CRUD modules: Cutoff Periods, Products, Bill of Materials (BOM)

## Prerequisites

| Tool | Version |
|---|---|
| Python | 3.12+ |
| Flutter | 3.x (stable) |
| Docker + Docker Compose | any recent version |
| PostgreSQL client (`psql`) | for the init script |

---

## Option A — Docker (recommended)

### 1. Configure environment

```powershell
cd c:\dev-app\bi_admin
copy .env.example .env
```

Edit `.env` and fill in:

```env
DB_HOST=your-postgres-host
DB_PORT=5432
DB_NAME=your_database
DB_USER=your_db_user
DB_PASSWORD=your_db_password

JWT_SECRET=<random 32-byte hex — see below>

SFTP_HOST=your-sftp-host
SFTP_PORT=22
SFTP_USER=sftp_service_account
SFTP_PASSWORD=sftp_password
SFTP_DATA_DIR=/data
SFTP_LOGS_DIR=/logs
SFTP_OUTPUT_DIR=/output

CORS_ORIGINS=http://localhost,http://localhost:80
```

Generate a JWT secret:
```powershell
python -c "import secrets; print(secrets.token_hex(32))"
```

### 2. Initialise the database (once)

```powershell
psql -h YOUR_HOST -U YOUR_USER -d YOUR_DB -f backend/scripts/init_db.sql
```

### 3. Start everything

```powershell
docker compose up --build
```

| Service | URL |
|---|---|
| Frontend | http://localhost |
| Backend API | http://localhost:8000/docs |

---

## Option B — Run directly (development)

Faster for day-to-day work — you get hot reload on both sides.

### Backend

```powershell
cd c:\dev-app\bi_admin\backend

python -m venv .venv
.venv\Scripts\Activate.ps1

pip install -r requirements.txt

# Copy and edit .env (same values as Option A)
copy ..\\.env.example .env

uvicorn app.main:app --reload --port 8000
```

API docs available at http://localhost:8000/docs

### Frontend (separate terminal)

```powershell
cd c:\dev-app\bi_admin\frontend

flutter run -d chrome --web-port 5000 --dart-define=API_BASE_URL=http://localhost:8000
```

Frontend opens at http://localhost:5000

---

## First login

After running the DB init script, log in with:

| Field | Value |
|---|---|
| Email | `admin@tyto-solutions.com` |
| Password | `Admin@1234` |

You will be forced to change the password immediately after first login.

---

## Project structure

```
bi_admin/
├── backend/
│   ├── app/
│   │   ├── main.py          # FastAPI app entry point
│   │   ├── config.py        # Settings from .env
│   │   ├── database.py      # asyncpg connection pool
│   │   ├── auth.py          # JWT + bcrypt helpers
│   │   ├── dependencies.py  # FastAPI auth dependencies
│   │   └── routers/
│   │       ├── auth.py      # Login, refresh, change-password
│   │       ├── users.py     # User management (super admin only)
│   │       ├── sftp.py      # SFTP browse/upload/download/delete/archive
│   │       ├── cutoff.py    # cutoff_period table
│   │       ├── products.py  # products table
│   │       └── bom.py       # products + bom join
│   ├── scripts/
│   │   └── init_db.sql      # Creates admin_users table and seeds super admin
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   └── lib/
│       ├── main.dart
│       ├── services/        # API client, session management
│       ├── screens/         # auth, sftp, cutoff, products, bom, admin
│       └── widgets/         # AppShell (sidebar nav), ErrorBanner
├── docker-compose.yml
└── .env.example
```
