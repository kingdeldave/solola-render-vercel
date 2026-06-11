# Refactor Solola : paramètres utilisateur et administration

## Objectif

Cette version sépare les paramètres visibles par l'utilisateur normal des paramètres système et administrateur.

## Nouvelles routes Flutter Web

- `/login` : connexion utilisateur par OTP.
- `/settings` : paramètres utilisateur, réservés aux utilisateurs connectés.
- `/admin/login` : connexion administrateur séparée.
- `/admin` : tableau de bord administrateur, rôle `ADMIN` obligatoire.
- `/admin/settings` : paramètres système en lecture, rôle `ADMIN` obligatoire.

## Rôles

Le backend utilise désormais un champ `role` dans la table `users` :

- `USER` : utilisateur normal.
- `ADMIN` : administrateur de l'application.

Un utilisateur normal ne peut pas accéder aux routes backend `/admin/*`.

## Paramètres utilisateur

La page utilisateur contient uniquement :

- Profil utilisateur.
- Photo de profil.
- Nom.
- Téléphone.
- Préférences d'affichage.
- Confidentialité.
- Notifications.
- Déconnexion.

Les éléments suivants ont été retirés du compte utilisateur :

- URL API backend.
- Configuration serveur.
- Logo global.
- Paramètres techniques.

## Configuration API

Flutter Web utilise `API_BASE_URL` injecté au build :

```bash
flutter build web --release --dart-define=API_BASE_URL=https://solola-backend.onrender.com
```

Sur Netlify, la variable à configurer est :

```env
API_BASE_URL=https://solola-backend.onrender.com
```

`VITE_API_URL` est mentionné uniquement comme alias documentaire si le projet migre un jour vers Vite/React. Flutter n'utilise pas `VITE_API_URL` directement.

## Backend Render

Variables recommandées :

```env
APP_ENV=production
SECRET_KEY=valeur-longue-aleatoire
DATABASE_PATH=solola.db
ADMIN_CODE=code-tracking-long
ADMIN_PHONE_NUMBER=+243000000000
ADMIN_BOOTSTRAP_PASSWORD=mot-de-passe-admin-temporaire
FRONTEND_ORIGIN=https://solola-front.netlify.app
TRACKING_ORIGIN=https://solola-tracking.netlify.app
OTP_DEMO_MODE=false
MAX_UPLOAD_MB=10
```

`ADMIN_PHONE_NUMBER` permet de promouvoir automatiquement en `ADMIN` un compte utilisateur avec ce numéro. Si `ADMIN_BOOTSTRAP_PASSWORD` est défini, le backend crée ou met à jour le mot de passe de cet administrateur au démarrage. Après le premier déploiement réussi, remplace ou supprime ce bootstrap selon ta politique de sécurité.

## Fichiers principaux modifiés

Frontend :

- `frontend_flutter/lib/main.dart`
- `frontend_flutter/lib/app.dart`
- `frontend_flutter/lib/core/route_guard.dart`
- `frontend_flutter/lib/pages/auth_page.dart`
- `frontend_flutter/lib/pages/home_page.dart`
- `frontend_flutter/lib/pages/admin_pages.dart`
- `frontend_flutter/.env.example`
- `netlify.toml`

Backend :

- `backend/app/app_runtime.py`
- `backend/app/sql/schema.sql`
- `backend/.env.example`
