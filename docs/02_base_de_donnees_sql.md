# Base de données SQL

Le schéma SQLite est dans :

```txt
backend/app/sql/schema.sql
```

Tables principales :

- `users` : utilisateurs, profil, confidentialité.
- `otp_codes` : codes d'inscription gratuits.
- `conversations` : discussions privées et groupes.
- `conversation_members` : membres des conversations.
- `messages` : messages texte, chiffrés ou fichiers.
- `files` et `file_deposits` : suivi des fichiers et SHA-256.
- `statuses` : photos de statut.
- `audit_logs` : journal de tracking.
- `app_settings` : paramètres admin.
