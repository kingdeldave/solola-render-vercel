# Restauration authentification Solola — email/mot de passe + OTP

## Objectif
Le système existant n'a pas été supprimé. Le flow OTP par téléphone (`/auth/otp/start` et `/auth/otp/verify`) reste disponible.

Une nouvelle authentification principale a été ajoutée :

1. L'utilisateur entre email + mot de passe sur `/login`.
2. Il choisit le canal : Email ou SMS.
3. Le backend génère un code OTP à 6 chiffres.
4. Le code est envoyé via email SMTP ou SMS/log serveur selon la configuration.
5. L'utilisateur est redirigé vers `/verify-code`.
6. Le backend vérifie le code, l'expiration et les tentatives.

## Routes ajoutées

### Utilisateur
- `POST /auth/login/start`
- `POST /auth/login/verify`
- `GET /verify-code` côté Flutter

### Admin
- `POST /admin/login/start`
- `POST /admin/login/verify`
- `/admin/login` côté Flutter conserve un design séparé.

## Routes conservées
- `POST /auth/otp/start`
- `POST /auth/otp/verify`
- `POST /auth/login`
- `POST /admin/login`

## Variables Render à ajouter

```env
ADMIN_EMAIL=admin@solola.app
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=no-reply@example.com
SMTP_PASSWORD=mot_de_passe_smtp
SMTP_FROM=no-reply@example.com
SMS_PROVIDER=console
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_FROM=
```

Sans SMTP configuré, le code email est écrit dans les logs Render. Aucun code n'est renvoyé au frontend.

## Fichiers modifiés
- `backend/app/app_runtime.py`
- `backend/app/sql/schema.sql`
- `backend/.env.example`
- `frontend_flutter/lib/main.dart`
- `frontend_flutter/lib/app.dart`
- `frontend_flutter/lib/pages/auth_page.dart`
- `frontend_flutter/lib/pages/admin_pages.dart`
- `frontend_flutter/lib/pages/verify_code_page.dart`
- `frontend_flutter/lib/pages/home_page.dart`
- `netlify.toml`

## Sécurité
- Code OTP hashé côté backend.
- Expiration : 10 minutes.
- Limite de tentatives : 5 tentatives par code.
- Rate limiting par IP et par email.
- Le code OTP n'est jamais affiché dans le frontend.
- L'admin utilise aussi OTP.
