from __future__ import annotations

import base64
import hashlib
import hmac
import json
import mimetypes
import os
import re
import secrets
import smtplib
import sqlite3
import time
import uuid
from collections import defaultdict
from datetime import datetime, timedelta
from email.message import EmailMessage
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator

BASE_DIR = Path(__file__).resolve().parent.parent
STATIC_DIR = BASE_DIR / "static"
UPLOAD_DIR = BASE_DIR / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)
load_dotenv(BASE_DIR / ".env")

APP_ENV = os.getenv("APP_ENV", "production" if os.getenv("RENDER") else "development").lower()
SECRET_KEY_RAW = os.getenv("SECRET_KEY")
ADMIN_CODE_RAW = os.getenv("ADMIN_CODE")

if APP_ENV == "production" and not SECRET_KEY_RAW:
    raise RuntimeError("SECRET_KEY doit être défini dans Render en production.")
if APP_ENV == "production" and not ADMIN_CODE_RAW:
    raise RuntimeError("ADMIN_CODE doit être défini dans les variables d'environnement Render.")

SECRET_KEY = (SECRET_KEY_RAW or "dev-only-solola-secret-change-me-32chars").encode("utf-8")
DATABASE_PATH = BASE_DIR / os.getenv("DATABASE_PATH", "solola.db")
ADMIN_CODE = ADMIN_CODE_RAW or "dev-admin-code-change-me"
FRONTEND_ORIGIN = os.getenv("FRONTEND_ORIGIN", "https://solola-front.netlify.app").strip()
TRACKING_ORIGIN = os.getenv("TRACKING_ORIGIN", "").strip()
ADMIN_PHONE_NUMBER = os.getenv("ADMIN_PHONE_NUMBER", "").strip()
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "").strip().lower()
ADMIN_BOOTSTRAP_PASSWORD = os.getenv("ADMIN_BOOTSTRAP_PASSWORD", "").strip()
SMTP_HOST = os.getenv("SMTP_HOST", "").strip()
SMTP_PORT = int(os.getenv("SMTP_PORT", "587") or "587")
SMTP_USER = os.getenv("SMTP_USER", "").strip()
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "").strip()
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USER or "no-reply@solola.app").strip()
SMS_PROVIDER = os.getenv("SMS_PROVIDER", "console").strip().lower()
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "").strip()
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "").strip()
TWILIO_FROM = os.getenv("TWILIO_FROM", "").strip()
OTP_DEMO_MODE = os.getenv("OTP_DEMO_MODE", "false").lower() in {"1", "true", "yes", "on"}
MAX_UPLOAD_SIZE = int(os.getenv("MAX_UPLOAD_MB", "10")) * 1024 * 1024

allowed_origins = [
    "http://localhost:3000",
    "http://localhost:5000",
    "http://localhost:8080",
]
for origin in [FRONTEND_ORIGIN, TRACKING_ORIGIN]:
    if origin and origin not in allowed_origins:
        allowed_origins.append(origin)

app = FastAPI(title="Solola API", version="7.1-secure")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_origin_regex=os.getenv("CORS_ORIGIN_REGEX", r"https://.*\.netlify\.app"),
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-Token"],
)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "img-src 'self' data: https:; "
        "style-src 'self' 'unsafe-inline'; "
        "script-src 'self' 'unsafe-inline'; "
        "connect-src 'self' https://solola-backend.onrender.com wss://solola-backend.onrender.com; "
        "frame-ancestors 'none';"
    )
    return response


def now() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def iso_after(hours: int) -> str:
    return (datetime.utcnow() + timedelta(hours=hours)).isoformat(timespec="seconds") + "Z"


def db() -> sqlite3.Connection:
    # Connexion SQLite robuste : évite les erreurs "database is locked"
    # quand FastAPI traite plusieurs requêtes proches dans le temps.
    c = sqlite3.connect(DATABASE_PATH, timeout=30)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys=ON")
    c.execute("PRAGMA busy_timeout=30000")
    try:
        # WAL améliore les lectures/écritures concurrentes sur SQLite.
        c.execute("PRAGMA journal_mode=WAL")
    except sqlite3.OperationalError:
        pass
    return c


def init_db() -> None:
    with db() as c:
        c.executescript((Path(__file__).resolve().parent / 'sql' / 'schema.sql').read_text(encoding='utf-8'))
        for sql in [
            "ALTER TABLE users ADD COLUMN avatar_file_id INTEGER",
            "ALTER TABLE users ADD COLUMN last_seen TEXT",
            "ALTER TABLE users ADD COLUMN privacy_show_online INTEGER NOT NULL DEFAULT 1",
            "ALTER TABLE users ADD COLUMN privacy_allow_calls INTEGER NOT NULL DEFAULT 1",
            "ALTER TABLE users ADD COLUMN privacy_allow_group_invites INTEGER NOT NULL DEFAULT 1",
            "ALTER TABLE users ADD COLUMN privacy_show_avatar INTEGER NOT NULL DEFAULT 1",
            "ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'USER'",
            "ALTER TABLE users ADD COLUMN email TEXT",
            "ALTER TABLE conversations ADD COLUMN is_secure INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE conversations ADD COLUMN security_hint TEXT DEFAULT ''",
        ]:
            try:
                c.execute(sql)
            except sqlite3.OperationalError:
                pass
        if ADMIN_PHONE_NUMBER:
            admin_phone = re.sub(r"\s+", "", ADMIN_PHONE_NUMBER)
            existing_admin = c.execute("SELECT id FROM users WHERE phone_number=?", (admin_phone,)).fetchone()
            ts = now()
            admin_email = ADMIN_EMAIL or None

            if existing_admin:
                c.execute(
                    "UPDATE users SET role='ADMIN', email=COALESCE(?, email), updated_at=? WHERE phone_number=?",
                    (admin_email, ts, admin_phone),
                )
                if ADMIN_BOOTSTRAP_PASSWORD:
                    c.execute(
                        "UPDATE users SET password_hash=?, updated_at=? WHERE phone_number=?",
                        (hpw(ADMIN_BOOTSTRAP_PASSWORD), ts, admin_phone),
                    )
            elif ADMIN_BOOTSTRAP_PASSWORD:
                uid = str(uuid.uuid4())
                c.execute(
                    """INSERT INTO users(id,phone_number,email,pseudo,password_hash,role,created_at,updated_at,last_seen)
                       VALUES(?,?,?,?,?,?,?,?,?)""",
                    (uid, admin_phone, admin_email, "Administrateur Solola", hpw(ADMIN_BOOTSTRAP_PASSWORD), "ADMIN", ts, ts, ts),
                )
        c.commit()


@app.on_event("startup")
def startup() -> None:
    init_db()
    ensure_runtime_tables()


def hpw(p: str) -> str:
    if len(p) < 6:
        raise HTTPException(400, "Le mot de passe doit avoir au moins 6 caractères")
    it = 260_000
    salt = secrets.token_hex(16)
    dig = hashlib.pbkdf2_hmac("sha256", p.encode(), salt.encode(), it).hex()
    return f"pbkdf2${it}${salt}${dig}"


def vpw(p: str, stored: str) -> bool:
    try:
        a, it, s, d = stored.split("$", 3)
        return a == "pbkdf2" and hmac.compare_digest(hashlib.pbkdf2_hmac("sha256", p.encode(), s.encode(), int(it)).hex(), d)
    except Exception:
        return False


def b64(x: bytes) -> str:
    return base64.urlsafe_b64encode(x).decode().rstrip("=")


def unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def token(uid: str) -> str:
    body = b64(json.dumps({"sub": uid, "exp": int(time.time()) + 7 * 24 * 3600}, separators=(",", ":")).encode())
    sig = b64(hmac.new(SECRET_KEY, body.encode(), hashlib.sha256).digest())
    return body + "." + sig


def uid_from_token(t: str) -> str:
    try:
        body, sig = t.split(".", 1)
        exp = b64(hmac.new(SECRET_KEY, body.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, exp):
            raise ValueError
        data = json.loads(unb64(body))
        if data["exp"] < int(time.time()):
            raise ValueError
        return data["sub"]
    except Exception:
        raise HTTPException(401, "Session invalide")


def user(authorization: str | None = Header(None)) -> dict[str, Any]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Non connecté")
    uid = uid_from_token(authorization.replace("Bearer ", "", 1).strip())
    with db() as c:
        r = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
        if not r:
            raise HTTPException(401, "Utilisateur introuvable")
        return dict(r)



def role_of(u: dict[str, Any]) -> str:
    return str(u.get("role") or "USER").upper()


def require_roles(*allowed_roles: str):
    allowed = {role.upper() for role in allowed_roles}

    def dependency(u=Depends(user)) -> dict[str, Any]:
        if role_of(u) not in allowed:
            raise HTTPException(403, "Accès refusé : rôle insuffisant")
        return u

    return dependency


def require_admin_user(u=Depends(user)) -> dict[str, Any]:
    if role_of(u) != "ADMIN":
        raise HTTPException(403, "Accès réservé aux administrateurs")
    return u




RATE_BUCKET: dict[str, list[float]] = defaultdict(list)
PHONE_RE = re.compile(r"^\+?[0-9]{8,15}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalize_email(value: str) -> str:
    clean = value.strip().lower()
    if not EMAIL_RE.match(clean):
        raise HTTPException(400, "Adresse email invalide")
    return clean


def normalize_phone(value: str) -> str:
    clean = re.sub(r"\s+", "", value.strip())
    if not PHONE_RE.match(clean):
        raise HTTPException(400, "Numéro de téléphone invalide")
    return clean


def client_ip(x_forwarded_for: str | None = Header(default=None)) -> str:
    if x_forwarded_for:
        return x_forwarded_for.split(",")[0].strip()
    return "unknown"


def rate_limit(key: str, limit: int, window_seconds: int) -> None:
    current = time.time()
    RATE_BUCKET[key] = [ts for ts in RATE_BUCKET[key] if current - ts < window_seconds]
    if len(RATE_BUCKET[key]) >= limit:
        raise HTTPException(429, "Trop de tentatives. Réessaie plus tard.")
    RATE_BUCKET[key].append(current)


def hash_otp(phone: str, code: str) -> str:
    raw = f"{phone}:{code}".encode("utf-8")
    return hmac.new(SECRET_KEY, raw, hashlib.sha256).hexdigest()


def mask_destination(value: str) -> str:
    if "@" in value:
        name, domain = value.split("@", 1)
        return f"{name[:2]}***@{domain}"
    if len(value) <= 4:
        return "****"
    return f"***{value[-4:]}"


def send_otp_email(email: str, code: str) -> None:
    if not SMTP_HOST:
        # Démo contrôlée : le code va dans les logs Render, jamais dans le frontend.
        print(f"[SOLOLA OTP EMAIL] Code pour {email}: {code}")
        return

    msg = EmailMessage()
    msg["Subject"] = "Code de vérification Solola"
    msg["From"] = SMTP_FROM
    msg["To"] = email
    msg.set_content(
        "Bonjour,\n\n"
        f"Votre code de vérification Solola est : {code}\n"
        "Ce code expire dans 10 minutes. Ne le partagez avec personne.\n\n"
        "Solola Security"
    )

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as smtp:
        smtp.starttls()
        if SMTP_USER and SMTP_PASSWORD:
            smtp.login(SMTP_USER, SMTP_PASSWORD)
        smtp.send_message(msg)


def send_otp_sms(phone: str, code: str) -> None:
    # Intégration SMS réelle à brancher via Twilio/Vonage/Orange API.
    # Par sécurité, sans fournisseur configuré, le code part uniquement dans les logs Render.
    print(f"[SOLOLA OTP SMS] Code pour {phone}: {code}")


def deliver_otp_to_user(row: sqlite3.Row | dict[str, Any], channel: str, code: str) -> str:
    selected = channel.lower().strip()
    if selected not in {"email", "sms"}:
        raise HTTPException(400, "Canal OTP invalide")

    user_email = str(row["email"] or "").strip().lower() if "email" in row.keys() else ""
    phone = str(row["phone_number"] or "").strip()

    if selected == "email":
        if not user_email:
            raise HTTPException(400, "Aucun email n'est enregistré pour ce compte")
        send_otp_email(user_email, code)
        return mask_destination(user_email)

    if not phone:
        raise HTTPException(400, "Aucun numéro de téléphone n'est enregistré pour ce compte")
    send_otp_sms(phone, code)
    return mask_destination(phone)


def deliver_otp(phone: str, code: str) -> None:
    # Compatibilité avec l'ancien flow OTP par téléphone.
    send_otp_sms(phone, code)


async def read_limited_upload(upload: UploadFile, max_size: int = MAX_UPLOAD_SIZE) -> bytes:
    content = await upload.read(max_size + 1)
    if len(content) > max_size:
        raise HTTPException(413, "Fichier trop lourd")
    return content


def validate_mime(mime: str | None, *, image_only: bool = False) -> None:
    allowed_files = {
        "image/jpeg", "image/png", "image/webp", "image/gif",
        "application/pdf", "text/plain",
        "application/zip", "application/octet-stream",
    }
    if image_only:
        if not (mime or "").startswith("image/"):
            raise HTTPException(400, "Le fichier doit être une image")
        return
    if mime not in allowed_files:
        raise HTTPException(400, "Type de fichier non autorisé")


def optional_user_from_authorization(authorization: str | None) -> dict[str, Any] | None:
    if not authorization or not authorization.startswith("Bearer "):
        return None
    try:
        return user(authorization)
    except HTTPException:
        return None


def pub(r: sqlite3.Row | dict[str, Any] | None) -> dict[str, Any] | None:
    if not r:
        return None
    d = dict(r)
    avatar_id = d.get("avatar_file_id")
    return {
        "id": d["id"],
        "phone_number": d["phone_number"],
        "email": d.get("email") or "",
        "pseudo": d["pseudo"],
        "info": d.get("info") or "",
        "role": str(d.get("role") or "USER").upper(),
        "avatar_file_id": avatar_id,
        "avatar_url": f"/files/{avatar_id}/download" if avatar_id and int(d.get("privacy_show_avatar", 1) or 0) else None,
        "last_seen": d.get("last_seen") if int(d.get("privacy_show_online", 1) or 0) else None,
        "privacy": {
            "show_online": bool(int(d.get("privacy_show_online", 1) or 0)),
            "allow_calls": bool(int(d.get("privacy_allow_calls", 1) or 0)),
            "allow_group_invites": bool(int(d.get("privacy_allow_group_invites", 1) or 0)),
            "show_avatar": bool(int(d.get("privacy_show_avatar", 1) or 0)),
        },
    }



def ensure_runtime_tables() -> None:
    """Crée les tables ajoutées après les premières versions du projet.

    Cette fonction sert de migration légère : elle répare automatiquement
    les anciennes bases `solola.db` sans devoir supprimer les comptes existants.
    """
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS otp_codes(
            phone_number TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            channel TEXT DEFAULT 'email',
            purpose TEXT DEFAULT 'login'
        );

        CREATE TABLE IF NOT EXISTS app_settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """)
        for sql in [
            "ALTER TABLE otp_codes ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE otp_codes ADD COLUMN channel TEXT DEFAULT 'email'",
            "ALTER TABLE otp_codes ADD COLUMN purpose TEXT DEFAULT 'login'",
            "ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'USER'",
            "ALTER TABLE users ADD COLUMN email TEXT",
        ]:
            try:
                c.execute(sql)
            except sqlite3.OperationalError:
                pass
        if ADMIN_PHONE_NUMBER:
            admin_phone = re.sub(r"\s+", "", ADMIN_PHONE_NUMBER)
            if ADMIN_EMAIL:
                c.execute("UPDATE users SET role='ADMIN', email=COALESCE(email, ?) WHERE phone_number=?", (ADMIN_EMAIL, admin_phone))
            else:
                c.execute("UPDATE users SET role='ADMIN' WHERE phone_number=?", (admin_phone,))
        c.commit()


def ensure_otp_table() -> None:
    # Compatibilité avec les anciennes routes qui appellent encore ensure_otp_table().
    ensure_runtime_tables()



def audit(uid: str | None, action: str, details: dict[str, Any] | None = None) -> None:
    try:
        ensure_runtime_tables()
        with db() as c:
            c.execute(
                "INSERT INTO audit_logs(user_id,action,details,created_at) VALUES(?,?,?,?)",
                (uid, action, json.dumps(details or {}, ensure_ascii=False), now()),
            )
            c.commit()
    except sqlite3.OperationalError:
        # L'audit ne doit jamais bloquer l'inscription, la connexion ou l'envoi de messages.
        pass


def current_admin_code() -> str:
    try:
        ensure_runtime_tables()
        with db() as c:
            row = c.execute("SELECT value FROM app_settings WHERE key='admin_code'").fetchone()
            if row and row["value"]:
                return row["value"]
    except Exception:
        pass
    return ADMIN_CODE


def set_admin_code(new_code: str) -> None:
    ensure_runtime_tables()
    with db() as c:
        c.execute("""
            INSERT INTO app_settings(key, value, updated_at)
            VALUES('admin_code', ?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at
        """, (new_code, now()))
        c.commit()


def admin_token(code: str | None = None) -> str:
    payload = {
        "scope": "tracking",
        "exp": int(time.time()) + 2 * 3600,
    }
    body = b64(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    raw = f"{body}:{code or current_admin_code()}".encode("utf-8")
    sig = b64(hmac.new(SECRET_KEY, raw, hashlib.sha256).digest())
    return f"{body}.{sig}"


def verify_admin_token(value: str) -> bool:
    try:
        body, sig = value.split(".", 1)
        payload = json.loads(unb64(body))
        if payload.get("scope") != "tracking":
            return False
        if int(payload.get("exp", 0)) < int(time.time()):
            return False
        expected = b64(hmac.new(SECRET_KEY, f"{body}:{current_admin_code()}".encode("utf-8"), hashlib.sha256).digest())
        return hmac.compare_digest(sig, expected)
    except Exception:
        return False


def require_tracking_admin(x_admin_token: str | None = Header(default=None)) -> None:
    if not x_admin_token or not verify_admin_token(x_admin_token):
        raise HTTPException(401, "Accès tracking refusé ou session expirée")


class RegisterIn(BaseModel):
    phone_number: str = Field(..., min_length=8, max_length=15)
    pseudo: str = Field(..., min_length=2, max_length=40)
    password: str = Field(..., min_length=8, max_length=128)
    email: str = Field(default="", max_length=160)

    @field_validator("phone_number")
    @classmethod
    def valid_phone(cls, value: str) -> str:
        return normalize_phone(value)

    @field_validator("email")
    @classmethod
    def valid_email(cls, value: str) -> str:
        if not value.strip():
            return ""
        return normalize_email(value)


class LoginIn(BaseModel):
    phone_number: str = Field(..., min_length=8, max_length=15)
    password: str = Field(..., min_length=1, max_length=128)

    @field_validator("phone_number")
    @classmethod
    def valid_phone(cls, value: str) -> str:
        return normalize_phone(value)




class LoginStartIn(BaseModel):
    email: str = Field(..., min_length=5, max_length=160)
    password: str = Field(..., min_length=1, max_length=128)
    channel: str = Field(default="email", max_length=12)

    @field_validator("email")
    @classmethod
    def valid_email(cls, value: str) -> str:
        return normalize_email(value)

    @field_validator("channel")
    @classmethod
    def valid_channel(cls, value: str) -> str:
        channel = value.strip().lower()
        if channel not in {"email", "sms"}:
            raise ValueError("Canal de vérification invalide")
        return channel


class LoginVerifyIn(BaseModel):
    email: str = Field(..., min_length=5, max_length=160)
    code: str = Field(..., min_length=6, max_length=6)

    @field_validator("email")
    @classmethod
    def valid_email(cls, value: str) -> str:
        return normalize_email(value)


class OtpStartIn(BaseModel):
    phone_number: str = Field(..., min_length=8, max_length=15)

    @field_validator("phone_number")
    @classmethod
    def valid_phone(cls, value: str) -> str:
        return normalize_phone(value)


class OtpVerifyIn(BaseModel):
    phone_number: str = Field(..., min_length=8, max_length=15)
    code: str = Field(..., min_length=6, max_length=6)
    pseudo: str = Field(default="", max_length=40)

    @field_validator("phone_number")
    @classmethod
    def valid_phone(cls, value: str) -> str:
        return normalize_phone(value)


class ProfileIn(BaseModel):
    pseudo: str = Field(..., min_length=2, max_length=40)
    info: str = Field(default="", max_length=160)
    email: str = Field(default="", max_length=160)

    @field_validator("email")
    @classmethod
    def valid_email(cls, value: str) -> str:
        if not value.strip():
            return ""
        return normalize_email(value)


class PrivacyIn(BaseModel):
    show_online: bool = True
    allow_calls: bool = True
    allow_group_invites: bool = True
    show_avatar: bool = True


class AdminLoginIn(BaseModel):
    code: str


class ChangeAdminCodeIn(BaseModel):
    current_code: str = Field(..., min_length=8, max_length=128)
    new_code: str = Field(..., min_length=12, max_length=128)


class PrivateIn(BaseModel):
    phone_number: str = Field(..., min_length=8, max_length=15)
    is_secure: bool = False
    security_hint: str = Field(default="", max_length=120)

    @field_validator("phone_number")
    @classmethod
    def valid_phone(cls, value: str) -> str:
        return normalize_phone(value)


class GroupIn(BaseModel):
    title: str = Field(..., min_length=2, max_length=80)
    member_phone_numbers: list[str] = []
    is_secure: bool = False
    security_hint: str = Field(default="", max_length=120)


class MessageIn(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)
    message_type: str = "text"

    @field_validator("message_type")
    @classmethod
    def valid_message_type(cls, value: str) -> str:
        if value not in {"text", "encrypted_text"}:
            raise ValueError("Type de message invalide")
        return value


class ForwardIn(BaseModel):
    conversation_id: int


class MemberIn(BaseModel):
    phone_number: str


def require_member(c: sqlite3.Connection, cid: int, uid: str) -> None:
    if not c.execute("SELECT 1 FROM conversation_members WHERE conversation_id=? AND user_id=?", (cid, uid)).fetchone():
        raise HTTPException(403, "Vous n'êtes pas membre de cette conversation")


def require_admin(c: sqlite3.Connection, cid: int, uid: str) -> None:
    r = c.execute("SELECT role FROM conversation_members WHERE conversation_id=? AND user_id=?", (cid, uid)).fetchone()
    if not r or r["role"] != "admin":
        raise HTTPException(403, "Action réservée à l'administrateur du groupe")


def members(c: sqlite3.Connection, cid: int) -> list[str]:
    return [r["user_id"] for r in c.execute("SELECT user_id FROM conversation_members WHERE conversation_id=?", (cid,)).fetchall()]


def unread_count(c: sqlite3.Connection, cid: int, uid: str) -> int:
    row = c.execute("""
        SELECT COUNT(*) AS n
        FROM messages m
        WHERE m.conversation_id=?
          AND m.sender_id != ?
          AND m.deleted_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM message_reads mr WHERE mr.message_id=m.id AND mr.user_id=?)
    """, (cid, uid, uid)).fetchone()
    return int(row["n"] if row else 0)


def file_out(c: sqlite3.Connection, fid: int | None, trace: bool = False) -> dict[str, Any] | None:
    if not fid:
        return None
    f = c.execute("""SELECT f.*, u.pseudo first_pseudo, u.phone_number first_phone
                     FROM files f JOIN users u ON u.id=f.first_uploader_id WHERE f.id=?""", (fid,)).fetchone()
    if not f:
        return None
    out = {"id": f["id"], "original_filename": f["original_filename"], "size": f["size"], "mime_type": f["mime_type"], "download_url": f"/files/{f['id']}/download"}
    if trace:
        deps = c.execute("""SELECT fd.*, u.pseudo, u.phone_number
                            FROM file_deposits fd JOIN users u ON u.id=fd.uploader_id
                            WHERE fd.file_id=? ORDER BY fd.id""", (fid,)).fetchall()
        out.update({
            "file_hash": f["file_hash"],
            "first_uploader": {"id": f["first_uploader_id"], "pseudo": f["first_pseudo"], "phone_number": f["first_phone"]},
            "first_uploaded_at": f["first_uploaded_at"],
            "first_conversation_id": f["first_conversation_id"],
            "deposits": [dict(d) for d in deps],
        })
    return out


def msg_out(c: sqlite3.Connection, m: sqlite3.Row | None) -> dict[str, Any] | None:
    if not m:
        return None
    s = c.execute("SELECT id,pseudo,phone_number,avatar_file_id,last_seen FROM users WHERE id=?", (m["sender_id"],)).fetchone()
    osender = c.execute("SELECT * FROM users WHERE id=?", (m["original_sender_id"],)).fetchone() if m["original_sender_id"] else None
    return {
        "id": m["id"],
        "conversation_id": m["conversation_id"],
        "sender_id": m["sender_id"],
        "sender_pseudo": s["pseudo"] if s else "Inconnu",
        "sender_phone": s["phone_number"] if s else "",
        "sender": pub(s) if s else None,
        "content": m["content"],
        "message_type": m["message_type"],
        "status": m["status"],
        "created_at": m["created_at"],
        "deleted_at": m["deleted_at"],
        "file": file_out(c, m["file_id"], False),
        "original_sender": pub(osender) if osender else None,
        "original_message_id": m["original_message_id"],
        "original_conversation_id": m["original_conversation_id"],
    }


def conv_out(c: sqlite3.Connection, conv: sqlite3.Row, current_uid: str) -> dict[str, Any]:
    mem = c.execute("""SELECT u.id,u.phone_number,u.pseudo,u.avatar_file_id,u.last_seen,cm.role,cm.joined_at
                       FROM conversation_members cm JOIN users u ON u.id=cm.user_id
                       WHERE cm.conversation_id=?""", (conv["id"],)).fetchall()
    title = conv["title"] or "Conversation"
    if conv["type"] == "private":
        other = [m for m in mem if m["id"] != current_uid]
        if other:
            title = other[0]["pseudo"]
    last = c.execute("SELECT * FROM messages WHERE conversation_id=? AND deleted_at IS NULL ORDER BY id DESC LIMIT 1", (conv["id"],)).fetchone()
    return {
        "id": conv["id"],
        "type": conv["type"],
        "title": conv["title"],
        "display_title": title,
        "created_at": conv["created_at"],
        "is_secure": bool(conv["is_secure"]) if "is_secure" in conv.keys() else False,
        "security_hint": conv["security_hint"] if "security_hint" in conv.keys() else "",
        "members": [pub(m) | {"role": m["role"], "joined_at": m["joined_at"]} for m in mem],
        "last_message": msg_out(c, last) if last else None,
        "unread_count": unread_count(c, conv["id"], current_uid),
    }


def status_out(c: sqlite3.Connection, sid: int) -> dict[str, Any] | None:
    r = c.execute("""SELECT s.*, u.pseudo,u.phone_number,u.avatar_file_id,u.last_seen
                     FROM statuses s JOIN users u ON u.id=s.user_id WHERE s.id=?""", (sid,)).fetchone()
    if not r:
        return None
    return {
        "id": r["id"],
        "caption": r["caption"],
        "created_at": r["created_at"],
        "expires_at": r["expires_at"],
        "user": pub({"id": r["user_id"], "phone_number": r["phone_number"], "pseudo": r["pseudo"], "info": "", "avatar_file_id": r["avatar_file_id"], "last_seen": r["last_seen"]}),
        "file": file_out(c, r["file_id"], False),
    }


class WSM:
    def __init__(self) -> None:
        self.conns: dict[str, list[WebSocket]] = {}

    def is_online(self, uid: str) -> bool:
        return bool(self.conns.get(uid))

    def online_ids(self) -> list[str]:
        return list(self.conns.keys())

    async def connect(self, uid: str, ws: WebSocket) -> None:
        await ws.accept()
        self.conns.setdefault(uid, []).append(ws)
        with db() as c:
            c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), uid))
            c.commit()
        await self.all({"type": "presence_update", "payload": {"user_id": uid, "online": True, "online_ids": self.online_ids(), "last_seen": now()}})

    def disconnect(self, uid: str, ws: WebSocket) -> None:
        xs = self.conns.get(uid, [])
        if ws in xs:
            xs.remove(ws)
        if not xs:
            self.conns.pop(uid, None)
            with db() as c:
                c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), uid))
                c.commit()

    async def send(self, uid: str, event: dict[str, Any]) -> None:
        for ws in list(self.conns.get(uid, [])):
            try:
                await ws.send_json(event)
            except Exception:
                self.disconnect(uid, ws)

    async def all(self, event: dict[str, Any]) -> None:
        for uid in list(self.conns):
            await self.send(uid, event)

    async def conv(self, c: sqlite3.Connection, cid: int, event: dict[str, Any]) -> None:
        for uid in members(c, cid):
            await self.send(uid, event)


wsman = WSM()


@app.get("/", response_class=HTMLResponse)
def home() -> str:
    return (STATIC_DIR / "index.html").read_text(encoding="utf-8")




def issue_login_otp(c: sqlite3.Connection, row: sqlite3.Row, channel: str, purpose: str) -> dict[str, Any]:
    code = f"{secrets.randbelow(1000000):06d}"
    expires_at = (datetime.utcnow() + timedelta(minutes=10)).isoformat(timespec="seconds") + "Z"
    phone = str(row["phone_number"])
    destination = deliver_otp_to_user(row, channel, code)

    c.execute("""
        INSERT INTO otp_codes(phone_number, code, expires_at, created_at, attempts, channel, purpose)
        VALUES(?,?,?,?,0,?,?)
        ON CONFLICT(phone_number) DO UPDATE SET
            code=excluded.code,
            expires_at=excluded.expires_at,
            created_at=excluded.created_at,
            attempts=0,
            channel=excluded.channel,
            purpose=excluded.purpose
    """, (phone, hash_otp(phone, code), expires_at, now(), channel, purpose))

    return {
        "message": "Code de vérification envoyé",
        "expires_in_minutes": 10,
        "channel": channel,
        "destination": destination,
    }


def verify_login_otp(c: sqlite3.Connection, row: sqlite3.Row, code: str, expected_purpose: str) -> None:
    phone = str(row["phone_number"])
    otp = c.execute("SELECT * FROM otp_codes WHERE phone_number=?", (phone,)).fetchone()

    if not otp:
        raise HTTPException(401, "Demande un nouveau code")

    if otp["expires_at"] < now():
        c.execute("DELETE FROM otp_codes WHERE phone_number=?", (phone,))
        c.commit()
        raise HTTPException(401, "Code expiré")

    purpose = otp["purpose"] if "purpose" in otp.keys() else "login"
    if purpose != expected_purpose:
        raise HTTPException(401, "Code non valide pour cette connexion")

    attempts = int(otp["attempts"] if "attempts" in otp.keys() else 0)
    if attempts >= 5:
        c.execute("DELETE FROM otp_codes WHERE phone_number=?", (phone,))
        c.commit()
        raise HTTPException(429, "Trop de tentatives. Demande un nouveau code.")

    if not hmac.compare_digest(otp["code"], hash_otp(phone, code.strip())):
        c.execute("UPDATE otp_codes SET attempts = attempts + 1 WHERE phone_number=?", (phone,))
        c.commit()
        raise HTTPException(401, "Code incorrect")

    c.execute("DELETE FROM otp_codes WHERE phone_number=?", (phone,))


@app.post("/auth/otp/start")
def otp_start(p: OtpStartIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    ensure_runtime_tables()
    phone = normalize_phone(p.phone_number)

    rate_limit(f"otp_start:ip:{ip}", limit=10, window_seconds=3600)
    rate_limit(f"otp_start:phone:{phone}", limit=5, window_seconds=3600)

    code = f"{secrets.randbelow(1000000):06d}"
    expires_at = (datetime.utcnow() + timedelta(minutes=10)).isoformat(timespec="seconds") + "Z"
    code_hash = hash_otp(phone, code)

    with db() as c:
        exists = c.execute("SELECT id FROM users WHERE phone_number=?", (phone,)).fetchone() is not None
        c.execute("""
            INSERT INTO otp_codes(phone_number, code, expires_at, created_at, attempts)
            VALUES(?,?,?,?,0)
            ON CONFLICT(phone_number) DO UPDATE SET
                code=excluded.code,
                expires_at=excluded.expires_at,
                created_at=excluded.created_at,
                attempts=0
        """, (phone, code_hash, expires_at, now()))
        c.commit()

    deliver_otp(phone, code)
    audit(None, "otp_requested", {"phone_number": phone, "is_new_user": not exists})

    response = {
        "message": "Code de vérification envoyé",
        "expires_in_minutes": 10,
        "is_new_user": not exists,
        "delivery": "demo_console" if OTP_DEMO_MODE else "external_provider_required",
    }
    return response


@app.post("/auth/otp/verify")
def otp_verify(p: OtpVerifyIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    ensure_runtime_tables()

    phone = normalize_phone(p.phone_number)
    code = p.code.strip()

    rate_limit(f"otp_verify:ip:{ip}", limit=20, window_seconds=3600)
    rate_limit(f"otp_verify:phone:{phone}", limit=8, window_seconds=900)

    audit_uid: str | None = None
    audit_action = "otp_login"
    audit_details: dict[str, Any] = {}

    with db() as c:
        otp = c.execute("SELECT * FROM otp_codes WHERE phone_number=?", (phone,)).fetchone()

        if not otp:
            raise HTTPException(401, "Demande un nouveau code")

        if otp["expires_at"] < now():
            c.execute("DELETE FROM otp_codes WHERE phone_number=?", (phone,))
            c.commit()
            raise HTTPException(401, "Code expiré")

        attempts = int(otp["attempts"] if "attempts" in otp.keys() else 0)
        if attempts >= 5:
            c.execute("DELETE FROM otp_codes WHERE phone_number=?", (phone,))
            c.commit()
            raise HTTPException(429, "Trop de tentatives. Demande un nouveau code.")

        if not hmac.compare_digest(otp["code"], hash_otp(phone, code)):
            c.execute("UPDATE otp_codes SET attempts = attempts + 1 WHERE phone_number=?", (phone,))
            c.commit()
            raise HTTPException(401, "Code incorrect")

        r = c.execute("SELECT * FROM users WHERE phone_number=?", (phone,)).fetchone()

        if not r:
            pseudo = p.pseudo.strip() or f"Solola {phone[-4:] if len(phone) >= 4 else phone}"
            uid = str(uuid.uuid4())
            ts = now()

            c.execute(
                "INSERT INTO users(id,phone_number,pseudo,password_hash,created_at,updated_at,last_seen) VALUES(?,?,?,?,?,?,?)",
                (uid, phone, pseudo, hpw(secrets.token_urlsafe(32)), ts, ts, ts),
            )
            r = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
            audit_uid = uid
            audit_action = "otp_register"
            audit_details = {"phone_number": phone}
        else:
            c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), r["id"]))
            audit_uid = r["id"]
            audit_action = "otp_login"
            audit_details = {}

        c.execute("DELETE FROM otp_codes WHERE phone_number=?", (phone,))
        c.commit()

    audit(audit_uid, audit_action, audit_details)

    return {"access_token": token(r["id"]), "token_type": "bearer", "user": pub(r)}


@app.post("/auth/register")
def register(p: RegisterIn) -> dict[str, Any]:
    with db() as c:
        phone = p.phone_number.strip()
        pseudo = p.pseudo.strip()
        email = p.email.strip().lower()
        if c.execute("SELECT id FROM users WHERE phone_number=?", (phone,)).fetchone():
            raise HTTPException(409, "Ce numéro est déjà utilisé. Clique sur Connexion.")
        if email and c.execute("SELECT id FROM users WHERE lower(email)=?", (email,)).fetchone():
            raise HTTPException(409, "Cet email est déjà utilisé.")
        uid = str(uuid.uuid4())
        ts = now()
        c.execute("INSERT INTO users(id,phone_number,email,pseudo,password_hash,created_at,updated_at,last_seen) VALUES(?,?,?,?,?,?,?,?)", (uid, phone, email or None, pseudo, hpw(p.password), ts, ts, ts))
        c.commit()
        r = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    audit(uid, "register", {"phone_number": phone})
    return {"access_token": token(uid), "token_type": "bearer", "user": pub(r)}




@app.post("/auth/login/start")
def login_start(p: LoginStartIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    ensure_runtime_tables()
    email = normalize_email(p.email)
    channel = p.channel.lower().strip()

    rate_limit(f"login_start:ip:{ip}", limit=10, window_seconds=900)
    rate_limit(f"login_start:email:{email}", limit=5, window_seconds=900)

    with db() as c:
        r = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
        if not r or not vpw(p.password, r["password_hash"]):
            audit(None, "login_start_failed", {"email": email})
            raise HTTPException(401, "Email ou mot de passe invalide")

        response = issue_login_otp(c, r, channel, "admin_login" if str(r["role"] or "").upper() == "ADMIN" else "login")
        c.commit()

    audit(r["id"], "login_otp_requested", {"channel": channel})
    return response


@app.post("/auth/login/verify")
def login_verify(p: LoginVerifyIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    ensure_runtime_tables()
    email = normalize_email(p.email)

    rate_limit(f"login_verify:ip:{ip}", limit=20, window_seconds=3600)
    rate_limit(f"login_verify:email:{email}", limit=8, window_seconds=900)

    with db() as c:
        r = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
        if not r:
            raise HTTPException(401, "Compte introuvable")

        expected = "admin_login" if str(r["role"] or "").upper() == "ADMIN" else "login"
        verify_login_otp(c, r, p.code, expected)
        c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), r["id"]))
        c.commit()

    audit(r["id"], "login_otp_verified", {})
    return {"access_token": token(r["id"]), "token_type": "bearer", "user": pub(r)}


@app.post("/auth/login")
def login(p: LoginIn) -> dict[str, Any]:
    with db() as c:
        r = c.execute("SELECT * FROM users WHERE phone_number=?", (p.phone_number.strip(),)).fetchone()
        if not r or not vpw(p.password, r["password_hash"]):
            raise HTTPException(401, "Numéro ou mot de passe invalide")
        c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), r["id"]))
        c.commit()
    audit(r["id"], "login", {})
    return {"access_token": token(r["id"]), "token_type": "bearer", "user": pub(r)}


@app.get("/auth/me")
def me(u=Depends(user)):
    return pub(u)




@app.post("/admin/login/start")
def admin_login_start(p: LoginStartIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    ensure_runtime_tables()
    email = normalize_email(p.email)
    channel = p.channel.lower().strip()

    rate_limit(f"admin_login_start:ip:{ip}", limit=8, window_seconds=900)
    rate_limit(f"admin_login_start:email:{email}", limit=5, window_seconds=900)

    with db() as c:
        r = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
        if not r or not vpw(p.password, r["password_hash"]):
            audit(None, "admin_login_start_failed", {"email": email})
            raise HTTPException(401, "Identifiants administrateur invalides")

        if str(r["role"] or "USER").upper() != "ADMIN":
            audit(r["id"], "admin_login_forbidden", {})
            raise HTTPException(403, "Accès réservé aux administrateurs")

        response = issue_login_otp(c, r, channel, "admin_login")
        c.commit()

    audit(r["id"], "admin_otp_requested", {"channel": channel})
    return response


@app.post("/admin/login/verify")
def admin_login_verify(p: LoginVerifyIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    ensure_runtime_tables()
    email = normalize_email(p.email)

    rate_limit(f"admin_login_verify:ip:{ip}", limit=20, window_seconds=3600)
    rate_limit(f"admin_login_verify:email:{email}", limit=8, window_seconds=900)

    with db() as c:
        r = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
        if not r:
            raise HTTPException(401, "Compte administrateur introuvable")
        if str(r["role"] or "USER").upper() != "ADMIN":
            raise HTTPException(403, "Accès réservé aux administrateurs")

        verify_login_otp(c, r, p.code, "admin_login")
        c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), r["id"]))
        c.commit()

    audit(r["id"], "admin_otp_verified", {})
    return {"access_token": token(r["id"]), "token_type": "bearer", "user": pub(r)}


@app.post("/admin/login")
def admin_login(p: LoginIn, ip: str = Depends(client_ip)) -> dict[str, Any]:
    rate_limit(f"admin_login:{ip}", limit=8, window_seconds=900)
    phone = normalize_phone(p.phone_number)

    with db() as c:
        r = c.execute("SELECT * FROM users WHERE phone_number=?", (phone,)).fetchone()

        if not r or not vpw(p.password, r["password_hash"]):
            audit(None, "admin_login_failed", {"phone_number": phone})
            raise HTTPException(401, "Identifiants administrateur invalides")

        if str(r["role"] or "USER").upper() != "ADMIN":
            audit(r["id"], "admin_login_forbidden", {})
            raise HTTPException(403, "Accès réservé aux administrateurs")

        c.execute("UPDATE users SET last_seen=? WHERE id=?", (now(), r["id"]))
        c.commit()

    audit(r["id"], "admin_login_success", {})
    return {"access_token": token(r["id"]), "token_type": "bearer", "user": pub(r)}


@app.get("/admin/me")
def admin_me(u=Depends(require_admin_user)):
    return pub(u)


@app.get("/admin/settings")
def admin_settings(_: dict[str, Any] = Depends(require_admin_user)):
    return {
        "api_url_source": "build-time API_BASE_URL / backend environment",
        "frontend_origin": FRONTEND_ORIGIN,
        "tracking_origin": TRACKING_ORIGIN,
        "otp_demo_mode": OTP_DEMO_MODE,
        "smtp_configured": bool(SMTP_HOST),
        "sms_provider": SMS_PROVIDER,
        "max_upload_mb": MAX_UPLOAD_SIZE // (1024 * 1024),
        "database_engine": "SQLite",
        "roles": ["USER", "ADMIN"],
    }


@app.patch("/auth/me/profile")
def profile(p: ProfileIn, u=Depends(user)):
    with db() as c:
        email = p.email.strip().lower()
        if email:
            owner = c.execute("SELECT id FROM users WHERE lower(email)=? AND id != ?", (email, u["id"])).fetchone()
            if owner:
                raise HTTPException(409, "Cet email est déjà utilisé")
        c.execute(
            "UPDATE users SET pseudo=?, info=?, email=COALESCE(?, email), updated_at=? WHERE id=?",
            (p.pseudo.strip(), p.info.strip(), email or None, now(), u["id"]),
        )
        c.commit()
        r = c.execute("SELECT * FROM users WHERE id=?", (u["id"],)).fetchone()
    return pub(r)


@app.patch("/auth/me/privacy")
def update_privacy(p: PrivacyIn, u=Depends(user)):
    with db() as c:
        c.execute("""UPDATE users
                     SET privacy_show_online=?, privacy_allow_calls=?, privacy_allow_group_invites=?,
                         privacy_show_avatar=?, updated_at=?
                     WHERE id=?""",
                  (1 if p.show_online else 0, 1 if p.allow_calls else 0,
                   1 if p.allow_group_invites else 0, 1 if p.show_avatar else 0,
                   now(), u["id"]))
        c.commit()
        r = c.execute("SELECT * FROM users WHERE id=?", (u["id"],)).fetchone()
    audit(u["id"], "privacy_updated", {
        "show_online": p.show_online,
        "allow_calls": p.allow_calls,
        "allow_group_invites": p.allow_group_invites,
        "show_avatar": p.show_avatar,
    })
    return pub(r)


@app.post("/auth/me/avatar")
async def update_avatar(upload: UploadFile = File(...), u=Depends(user)):
    content = await read_limited_upload(upload)
    if not content:
        raise HTTPException(400, "Image vide")
    original = Path(upload.filename or "avatar.jpg").name
    guessed_mime = mimetypes.guess_type(original)[0]
    mime = upload.content_type or guessed_mime or "image/jpeg"
    if mime == "application/octet-stream" and guessed_mime:
        mime = guessed_mime
    validate_mime(mime, image_only=True)
    h = hashlib.sha256(content).hexdigest()
    with db() as c:
        ex = c.execute("SELECT * FROM files WHERE file_hash=?", (h,)).fetchone()
        if ex:
            fid = ex["id"]
        else:
            storage = f"{uuid.uuid4()}_{original}"
            (UPLOAD_DIR / storage).write_bytes(content)
            fid = c.execute("""INSERT INTO files(file_hash,original_filename,storage_filename,size,mime_type,first_uploader_id,first_conversation_id,first_uploaded_at)
                               VALUES(?,?,?,?,?,?,0,?)""", (h, original, storage, len(content), mime, u["id"], now())).lastrowid
        c.execute("UPDATE users SET avatar_file_id=?, updated_at=? WHERE id=?", (fid, now(), u["id"]))
        c.commit()
        r = c.execute("SELECT * FROM users WHERE id=?", (u["id"],)).fetchone()
    audit(u["id"], "avatar_updated", {"file_hash": h})
    return pub(r)


@app.get("/presence")
def presence(u=Depends(user)):
    return {"online_ids": wsman.online_ids()}


@app.get("/conversations")
def conversations(u=Depends(user)):
    with db() as c:
        rows = c.execute("""SELECT c.* FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id
                            WHERE cm.user_id=? ORDER BY c.id DESC""", (u["id"],)).fetchall()
        return [conv_out(c, r, u["id"]) for r in rows]


@app.post("/conversations/private")
async def private(p: PrivateIn, u=Depends(user)):
    with db() as c:
        other = c.execute("SELECT * FROM users WHERE phone_number=?", (p.phone_number.strip(),)).fetchone()
        if not other:
            raise HTTPException(404, "Aucun utilisateur avec ce numéro")
        if other["id"] == u["id"]:
            raise HTTPException(400, "Impossible avec soi-même")
        ex = c.execute("""SELECT c.* FROM conversations c WHERE c.type='private'
                          AND EXISTS(SELECT 1 FROM conversation_members a WHERE a.conversation_id=c.id AND a.user_id=?)
                          AND EXISTS(SELECT 1 FROM conversation_members b WHERE b.conversation_id=c.id AND b.user_id=?)
                          AND IFNULL(c.is_secure,0)=?""", (u["id"], other["id"], 1 if p.is_secure else 0)).fetchone()
        if ex:
            return conv_out(c, ex, u["id"])
        cid = c.execute("INSERT INTO conversations(type,title,created_by,created_at,is_secure,security_hint) VALUES('private',NULL,?,?,?,?)", (u["id"], now(), 1 if p.is_secure else 0, p.security_hint.strip())).lastrowid
        for uid in [u["id"], other["id"]]:
            c.execute("INSERT INTO conversation_members(conversation_id,user_id,role,joined_at) VALUES(?,?,'member',?)", (cid, uid, now()))
        c.commit()
        conv = c.execute("SELECT * FROM conversations WHERE id=?", (cid,)).fetchone()
        a = conv_out(c, conv, u["id"])
        b = conv_out(c, conv, other["id"])
        await wsman.send(u["id"], {"type": "conversation_created", "payload": a})
        await wsman.send(other["id"], {"type": "conversation_created", "payload": b})
        audit(u["id"], "conversation_private_created", {"conversation_id": cid, "other_user_id": other["id"], "is_secure": p.is_secure})
        return a


@app.post("/conversations/group")
async def group(p: GroupIn, u=Depends(user)):
    with db() as c:
        cid = c.execute("INSERT INTO conversations(type,title,created_by,created_at,is_secure,security_hint) VALUES('group',?,?,?,?,?)", (p.title.strip(), u["id"], now(), 1 if p.is_secure else 0, p.security_hint.strip())).lastrowid
        added = {u["id"]}
        c.execute("INSERT INTO conversation_members(conversation_id,user_id,role,joined_at) VALUES(?,?,'admin',?)", (cid, u["id"], now()))
        for phone in p.member_phone_numbers:
            r = c.execute("SELECT * FROM users WHERE phone_number=?", (phone.strip(),)).fetchone()
            if r and r["id"] not in added and int(r["privacy_allow_group_invites"] if "privacy_allow_group_invites" in r.keys() else 1):
                added.add(r["id"])
                c.execute("INSERT OR IGNORE INTO conversation_members(conversation_id,user_id,role,joined_at) VALUES(?,?,'member',?)", (cid, r["id"], now()))
        c.commit()
        conv = c.execute("SELECT * FROM conversations WHERE id=?", (cid,)).fetchone()
        for uid in added:
            await wsman.send(uid, {"type": "conversation_created", "payload": conv_out(c, conv, uid)})
        audit(u["id"], "group_created", {"conversation_id": cid, "title": p.title.strip(), "member_count": len(added), "is_secure": p.is_secure})
        return conv_out(c, conv, u["id"])


@app.post("/conversations/{cid}/members")
async def add_member(cid: int, p: MemberIn, u=Depends(user)):
    with db() as c:
        require_admin(c, cid, u["id"])
        other = c.execute("SELECT * FROM users WHERE phone_number=?", (p.phone_number.strip(),)).fetchone()
        if not other:
            raise HTTPException(404, "Utilisateur introuvable")
        if not int(other["privacy_allow_group_invites"] if "privacy_allow_group_invites" in other.keys() else 1):
            raise HTTPException(403, "Cet utilisateur refuse les invitations de groupe")
        c.execute("INSERT OR IGNORE INTO conversation_members(conversation_id,user_id,role,joined_at) VALUES(?,?,'member',?)", (cid, other["id"], now()))
        c.commit()
        conv = c.execute("SELECT * FROM conversations WHERE id=?", (cid,)).fetchone()
        await wsman.conv(c, cid, {"type": "conversation_updated", "payload": conv_out(c, conv, u["id"])})
        await wsman.send(other["id"], {"type": "conversation_created", "payload": conv_out(c, conv, other["id"])})
        audit(u["id"], "group_member_added", {"conversation_id": cid, "member_id": other["id"]})
        return conv_out(c, conv, u["id"])


@app.delete("/conversations/{cid}/members/{member_id}")
async def remove_member(cid: int, member_id: str, u=Depends(user)):
    with db() as c:
        require_admin(c, cid, u["id"])
        if member_id == u["id"]:
            raise HTTPException(400, "L'admin ne peut pas se retirer ici")
        c.execute("DELETE FROM conversation_members WHERE conversation_id=? AND user_id=?", (cid, member_id))
        c.commit()
        conv = c.execute("SELECT * FROM conversations WHERE id=?", (cid,)).fetchone()
        await wsman.conv(c, cid, {"type": "conversation_updated", "payload": conv_out(c, conv, u["id"])})
        await wsman.send(member_id, {"type": "conversation_removed", "payload": {"conversation_id": cid}})
        audit(u["id"], "group_member_removed", {"conversation_id": cid, "member_id": member_id})
        return {"message": "Membre retiré"}


@app.get("/conversations/{cid}/messages")
def get_msgs(cid: int, u=Depends(user)):
    with db() as c:
        require_member(c, cid, u["id"])
        rows = c.execute("SELECT * FROM messages WHERE conversation_id=? ORDER BY id ASC", (cid,)).fetchall()
        return [msg_out(c, r) for r in rows]


@app.post("/conversations/{cid}/read")
async def mark_read(cid: int, u=Depends(user)):
    with db() as c:
        require_member(c, cid, u["id"])
        rows = c.execute("SELECT id FROM messages WHERE conversation_id=? AND sender_id!=? AND deleted_at IS NULL", (cid, u["id"])).fetchall()
        ts = now()
        for r in rows:
            c.execute("INSERT OR IGNORE INTO message_reads(message_id,user_id,read_at) VALUES(?,?,?)", (r["id"], u["id"], ts))
        c.execute("UPDATE messages SET status='read' WHERE conversation_id=? AND sender_id!=? AND deleted_at IS NULL", (cid, u["id"]))
        c.commit()
        await wsman.conv(c, cid, {"type": "messages_read", "payload": {"conversation_id": cid, "reader_id": u["id"]}})
    audit(u["id"], "conversation_read", {"conversation_id": cid})
    return {"message": "Lu"}


@app.post("/conversations/{cid}/messages")
async def send_msg(cid: int, p: MessageIn, u=Depends(user)):
    mtype = (p.message_type or "text").strip()
    if mtype not in {"text", "encrypted_text"}:
        mtype = "text"
    with db() as c:
        require_member(c, cid, u["id"])
        others = [x for x in members(c, cid) if x != u["id"]]
        status = "delivered" if any(wsman.is_online(x) for x in others) else "sent"
        mid = c.execute("INSERT INTO messages(conversation_id,sender_id,content,message_type,status,created_at) VALUES(?,?,?,?,?,?)", (cid, u["id"], p.content, mtype, status, now())).lastrowid
        c.execute("INSERT INTO message_reads(message_id,user_id,read_at) VALUES(?,?,?)", (mid, u["id"], now()))
        c.commit()
        out = msg_out(c, c.execute("SELECT * FROM messages WHERE id=?", (mid,)).fetchone())
        await wsman.conv(c, cid, {"type": "new_message", "payload": out})
    audit(u["id"], "message_sent", {"message_id": mid, "conversation_id": cid, "message_type": mtype})
    return out


@app.post("/conversations/{cid}/upload")
async def upload(
    cid: int,
    upload: UploadFile = File(...),
    message_type: str = Form("file"),
    encrypted_meta: str = Form(""),
    u=Depends(user),
):
    content = await read_limited_upload(upload)
    if not content:
        raise HTTPException(400, "Fichier vide")
    message_type = message_type if message_type in {"file", "encrypted_file"} else "file"
    h = hashlib.sha256(content).hexdigest()
    name = Path(upload.filename or "fichier").name
    mt = upload.content_type or mimetypes.guess_type(name)[0] or "application/octet-stream"
    validate_mime(mt, image_only=False)
    with db() as c:
        require_member(c, cid, u["id"])
        ex = c.execute("SELECT * FROM files WHERE file_hash=?", (h,)).fetchone()
        if ex:
            fid = ex["id"]
        else:
            st = f"{uuid.uuid4()}_{name}"
            (UPLOAD_DIR / st).write_bytes(content)
            fid = c.execute("""INSERT INTO files(file_hash,original_filename,storage_filename,size,mime_type,first_uploader_id,first_conversation_id,first_uploaded_at)
                               VALUES(?,?,?,?,?,?,?,?)""", (h, name, st, len(content), mt, u["id"], cid, now())).lastrowid
        msg_content = encrypted_meta if message_type == "encrypted_file" else name
        status = "delivered" if any(wsman.is_online(x) for x in members(c, cid) if x != u["id"]) else "sent"
        mid = c.execute("INSERT INTO messages(conversation_id,sender_id,content,message_type,status,file_id,created_at) VALUES(?,?,?,?,?,?,?)", (cid, u["id"], msg_content, message_type, status, fid, now())).lastrowid
        c.execute("INSERT INTO message_reads(message_id,user_id,read_at) VALUES(?,?,?)", (mid, u["id"], now()))
        c.execute("INSERT INTO file_deposits(file_id,uploader_id,conversation_id,message_id,original_filename,uploaded_at) VALUES(?,?,?,?,?,?)", (fid, u["id"], cid, mid, name, now()))
        c.commit()
        out = msg_out(c, c.execute("SELECT * FROM messages WHERE id=?", (mid,)).fetchone())
        await wsman.conv(c, cid, {"type": "new_message", "payload": out})
    audit(u["id"], "file_uploaded", {"file_id": fid, "file_hash": h, "message_type": message_type})
    return out


@app.get("/files/{fid}/download")
def download(fid: int, access_token: str | None = None, authorization: str | None = Header(default=None)):
    requester = optional_user_from_authorization(authorization)
    if not requester and access_token:
        requester = optional_user_from_authorization(f"Bearer {access_token}")
    with db() as c:
        f = c.execute("SELECT * FROM files WHERE id=?", (fid,)).fetchone()
        if not f:
            raise HTTPException(404, "Fichier introuvable")

        # Les fichiers de conversations sont privés : seul un membre de la conversation peut les ouvrir.
        message_link = c.execute("SELECT conversation_id FROM messages WHERE file_id=? AND deleted_at IS NULL LIMIT 1", (fid,)).fetchone()
        if message_link:
            if not requester:
                raise HTTPException(401, "Authentification requise pour ce fichier")
            require_member(c, int(message_link["conversation_id"]), requester["id"])

        # Les avatars et statuts restent accessibles publiquement via URL, car les balises Image Web
        # ne peuvent pas envoyer facilement un header Authorization.
        is_avatar_or_status = bool(
            c.execute("SELECT 1 FROM users WHERE avatar_file_id=? LIMIT 1", (fid,)).fetchone()
            or c.execute("SELECT 1 FROM statuses WHERE file_id=? LIMIT 1", (fid,)).fetchone()
        )
        if not message_link and not is_avatar_or_status and requester and f["first_uploader_id"] != requester["id"]:
            raise HTTPException(403, "Accès fichier refusé")

    p = UPLOAD_DIR / f["storage_filename"]
    if not p.exists():
        raise HTTPException(404, "Fichier physique introuvable")
    return FileResponse(str(p), media_type=f["mime_type"], filename=f["original_filename"])


@app.post("/statuses")
async def make_status(caption: str = Form(""), upload: UploadFile = File(...), u=Depends(user)):
    content = await read_limited_upload(upload)
    if not content:
        raise HTTPException(400, "Image vide")
    h = hashlib.sha256(content).hexdigest()
    name = Path(upload.filename or "status.jpg").name
    guessed_mime = mimetypes.guess_type(name)[0]
    mt = upload.content_type or guessed_mime or "image/jpeg"
    if mt == "application/octet-stream" and guessed_mime:
        mt = guessed_mime
    validate_mime(mt, image_only=True)
    with db() as c:
        ex = c.execute("SELECT * FROM files WHERE file_hash=?", (h,)).fetchone()
        if ex:
            fid = ex["id"]
        else:
            st = f"{uuid.uuid4()}_{name}"
            (UPLOAD_DIR / st).write_bytes(content)
            fid = c.execute("""INSERT INTO files(file_hash,original_filename,storage_filename,size,mime_type,first_uploader_id,first_conversation_id,first_uploaded_at)
                               VALUES(?,?,?,?,?,?,0,?)""", (h, name, st, len(content), mt, u["id"], now())).lastrowid
        sid = c.execute("INSERT INTO statuses(user_id,file_id,caption,created_at,expires_at) VALUES(?,?,?,?,?)", (u["id"], fid, caption.strip(), now(), iso_after(24))).lastrowid
        c.commit()
        out = status_out(c, sid)
        await wsman.all({"type": "new_status", "payload": out})
    audit(u["id"], "status_created", {"status_id": sid, "file_hash": h})
    return out


@app.get("/statuses")
def list_statuses(u=Depends(user)):
    with db() as c:
        rows = c.execute("SELECT id FROM statuses WHERE expires_at IS NULL OR expires_at > ? ORDER BY id DESC LIMIT 50", (now(),)).fetchall()
        return [status_out(c, r["id"]) for r in rows]


@app.delete("/statuses/{sid}")
async def delete_status(sid: int, u=Depends(user)):
    with db() as c:
        r = c.execute("SELECT * FROM statuses WHERE id=?", (sid,)).fetchone()
        if not r:
            raise HTTPException(404, "Statut introuvable")
        if r["user_id"] != u["id"]:
            raise HTTPException(403, "Seul l'auteur peut supprimer ce statut")
        c.execute("DELETE FROM statuses WHERE id=?", (sid,))
        c.commit()

    audit(u["id"], "status_deleted", {"status_id": sid})
    await wsman.all({"type": "status_deleted", "payload": {"id": sid, "user_id": u["id"]}})
    return {"message": "Statut supprimé", "id": sid}


@app.post("/messages/{mid}/forward")
async def forward(mid: int, p: ForwardIn, u=Depends(user)):
    with db() as c:
        m = c.execute("SELECT * FROM messages WHERE id=? AND deleted_at IS NULL", (mid,)).fetchone()
        if not m:
            raise HTTPException(404, "Message introuvable")
        require_member(c, m["conversation_id"], u["id"])
        require_member(c, p.conversation_id, u["id"])
        nid = c.execute("""INSERT INTO messages(conversation_id,sender_id,content,message_type,status,file_id,original_sender_id,original_message_id,original_conversation_id,forwarded_by_id,forwarded_at,created_at)
                           VALUES(?,?,?,'transfer','sent',?,?,?,?,?,?,?)""", (p.conversation_id, u["id"], m["content"], m["file_id"], m["sender_id"], m["id"], m["conversation_id"], u["id"], now(), now())).lastrowid
        c.commit()
        out = msg_out(c, c.execute("SELECT * FROM messages WHERE id=?", (nid,)).fetchone())
        await wsman.conv(c, p.conversation_id, {"type": "new_message", "payload": out})
    return out


@app.delete("/messages/{mid}")
async def delete_msg(mid: int, u=Depends(user)):
    with db() as c:
        m = c.execute("SELECT * FROM messages WHERE id=? AND deleted_at IS NULL", (mid,)).fetchone()
        if not m:
            raise HTTPException(404, "Message introuvable")
        if m["sender_id"] != u["id"]:
            raise HTTPException(403, "Seul l'auteur peut supprimer ce message")
        c.execute("UPDATE messages SET deleted_at=? WHERE id=?", (now(), mid))
        c.commit()
        await wsman.conv(c, m["conversation_id"], {"type": "message_deleted", "payload": {"id": mid, "conversation_id": m["conversation_id"]}})
    audit(u["id"], "message_deleted", {"message_id": mid})
    return {"message": "Message supprimé"}


@app.post("/tracking/login")
def tracking_login(p: AdminLoginIn, ip: str = Depends(client_ip)):
    rate_limit(f"tracking_login:{ip}", limit=5, window_seconds=900)
    if not hmac.compare_digest(p.code, current_admin_code()):
        audit(None, "tracking_admin_login_failed", {})
        raise HTTPException(401, "Code administrateur incorrect")
    audit(None, "tracking_admin_login_success", {})
    return {"admin_token": admin_token(p.code)}


@app.patch("/tracking/admin-code")
def change_tracking_admin_code(p: ChangeAdminCodeIn, _: None = Depends(require_tracking_admin)):
    if not hmac.compare_digest(p.current_code, current_admin_code()):
        audit(None, "tracking_admin_code_change_failed", {})
        raise HTTPException(401, "Code actuel incorrect")
    if len(p.new_code.strip()) < 12:
        raise HTTPException(400, "Le nouveau code doit contenir au moins 12 caractères")
    set_admin_code(p.new_code.strip())
    audit(None, "tracking_admin_code_changed", {})
    return {"message": "Code administrateur modifié", "admin_token": admin_token(p.new_code.strip())}


@app.get("/tracking/dashboard")
def tracking_dashboard(_: None = Depends(require_tracking_admin)):
    with db() as c:
        q = lambda sql: int(c.execute(sql).fetchone()[0] or 0)
        totals = {
            "users": q("SELECT COUNT(*) FROM users"),
            "conversations": q("SELECT COUNT(*) FROM conversations"),
            "secure_conversations": q("SELECT COUNT(*) FROM conversations WHERE IFNULL(is_secure,0)=1"),
            "messages": q("SELECT COUNT(*) FROM messages"),
            "encrypted_messages": q("SELECT COUNT(*) FROM messages WHERE message_type='encrypted_text'"),
            "deleted_messages": q("SELECT COUNT(*) FROM messages WHERE deleted_at IS NOT NULL"),
            "files": q("SELECT COUNT(*) FROM files WHERE first_conversation_id != 0"),
            "statuses": q("SELECT COUNT(*) FROM statuses"),
            "audit_logs": q("SELECT COUNT(*) FROM audit_logs"),
        }
        top_users = c.execute("""
            SELECT u.pseudo, u.phone_number, COUNT(m.id) AS total
            FROM users u LEFT JOIN messages m ON m.sender_id=u.id
            GROUP BY u.id ORDER BY total DESC LIMIT 5
        """).fetchall()
        recent = c.execute("""
            SELECT a.*, u.pseudo, u.phone_number
            FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id
            ORDER BY a.id DESC LIMIT 10
        """).fetchall()
        return {
            "totals": totals,
            "top_users": [dict(r) for r in top_users],
            "recent_audit": [dict(r) for r in recent],
        }


@app.get("/tracking/audit")
def tracking_audit(_: None = Depends(require_tracking_admin)):
    with db() as c:
        rows = c.execute("""
            SELECT a.*, u.pseudo, u.phone_number
            FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id
            ORDER BY a.id DESC LIMIT 500
        """).fetchall()
        return [dict(r) for r in rows]


@app.get("/tracking/messages")
def tracking_messages(_: None = Depends(require_tracking_admin)):
    with db() as c:
        rows = c.execute("""SELECT m.*,u.pseudo,u.phone_number,c.type conversation_type,c.title conversation_title,
                                  c.is_secure conversation_is_secure, c.security_hint conversation_security_hint
                           FROM messages m JOIN users u ON u.id=m.sender_id JOIN conversations c ON c.id=m.conversation_id
                           ORDER BY m.id DESC LIMIT 600""").fetchall()
        return [{
            "id": r["id"], "created_at": r["created_at"], "deleted_at": r["deleted_at"], "pseudo": r["pseudo"], "phone_number": r["phone_number"],
            "conversation_id": r["conversation_id"], "conversation_title": r["conversation_title"] or ("Conversation privée" if r["conversation_type"] == "private" else "Groupe"),
            "message_type": r["message_type"], "status": r["status"], "conversation_is_secure": bool(r["conversation_is_secure"]),
            "conversation_security_hint": r["conversation_security_hint"] or "", "content": r["content"], "file_id": r["file_id"],
        } for r in rows]


@app.get("/tracking/files")
def tracking_files(_: None = Depends(require_tracking_admin)):
    with db() as c:
        return [file_out(c, r["id"], True) for r in c.execute("SELECT id FROM files WHERE first_conversation_id != 0 ORDER BY id DESC").fetchall()]


@app.get("/tracking/statuses")
def tracking_statuses(_: None = Depends(require_tracking_admin)):
    with db() as c:
        rows = c.execute("""SELECT s.*, u.pseudo,u.phone_number, f.original_filename, f.file_hash, f.size, f.mime_type
                           FROM statuses s JOIN users u ON u.id=s.user_id JOIN files f ON f.id=s.file_id
                           ORDER BY s.id DESC LIMIT 300""").fetchall()
        return [dict(r) for r in rows]


@app.get("/tracking", response_class=HTMLResponse)
def tracking():
    return (STATIC_DIR / "tracking.html").read_text(encoding="utf-8")


@app.websocket("/ws")
async def websocket(ws: WebSocket):
    t = ws.query_params.get("token")
    if not t:
        await ws.close(code=1008)
        return
    try:
        uid = uid_from_token(t)
    except HTTPException:
        await ws.close(code=1008)
        return
    await wsman.connect(uid, ws)
    try:
        while True:
            data = await ws.receive_json()
            kind = data.get("type")
            if kind == "ping":
                await ws.send_json({"type": "pong", "online_ids": wsman.online_ids()})
            if kind in {"call_invite", "call_accept", "call_reject", "call_end", "webrtc_offer", "webrtc_answer", "webrtc_ice"}:
                target = data.get("to")
                if target:
                    data["from"] = uid
                    await wsman.send(target, data)
    except WebSocketDisconnect:
        wsman.disconnect(uid, ws)
        await wsman.all({"type": "presence_update", "payload": {"user_id": uid, "online": False, "online_ids": wsman.online_ids(), "last_seen": now()}})
