-- Solola database schema
-- Ce fichier centralise les tables SQLite utilisées par le backend.

CREATE TABLE IF NOT EXISTS users(
    id TEXT PRIMARY KEY,
    phone_number TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE,
    pseudo TEXT NOT NULL,
    info TEXT DEFAULT 'Disponible',
    avatar_file_id INTEGER,
    last_seen TEXT,
    privacy_show_online INTEGER NOT NULL DEFAULT 1,
    privacy_allow_calls INTEGER NOT NULL DEFAULT 1,
    privacy_allow_group_invites INTEGER NOT NULL DEFAULT 1,
    privacy_show_avatar INTEGER NOT NULL DEFAULT 1,
    role TEXT NOT NULL DEFAULT 'USER',
    password_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS conversations(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL CHECK(type IN ('private','group')),
    title TEXT,
    created_by TEXT,
    created_at TEXT NOT NULL,
    is_secure INTEGER NOT NULL DEFAULT 0,
    security_hint TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS conversation_members(
    conversation_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT DEFAULT 'member',
    joined_at TEXT NOT NULL,
    PRIMARY KEY(conversation_id,user_id)
);

CREATE TABLE IF NOT EXISTS files(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_hash TEXT UNIQUE NOT NULL,
    original_filename TEXT NOT NULL,
    storage_filename TEXT NOT NULL,
    size INTEGER NOT NULL,
    mime_type TEXT,
    first_uploader_id TEXT NOT NULL,
    first_conversation_id INTEGER NOT NULL,
    first_uploaded_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS file_deposits(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL,
    uploader_id TEXT NOT NULL,
    conversation_id INTEGER NOT NULL,
    message_id INTEGER,
    original_filename TEXT NOT NULL,
    uploaded_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL,
    sender_id TEXT NOT NULL,
    content TEXT,
    message_type TEXT NOT NULL DEFAULT 'text',
    status TEXT NOT NULL DEFAULT 'sent',
    file_id INTEGER,
    original_sender_id TEXT,
    original_message_id INTEGER,
    original_conversation_id INTEGER,
    forwarded_by_id TEXT,
    forwarded_at TEXT,
    created_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS message_reads(
    message_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    read_at TEXT NOT NULL,
    PRIMARY KEY(message_id,user_id)
);

CREATE TABLE IF NOT EXISTS statuses(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    file_id INTEGER NOT NULL,
    caption TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    expires_at TEXT
);

CREATE TABLE IF NOT EXISTS audit_logs(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    action TEXT NOT NULL,
    details TEXT,
    created_at TEXT NOT NULL
);

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
