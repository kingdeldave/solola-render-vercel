# Solola - Vérification email Firebase côté frontend

Cette version ajoute une couche **Firebase Authentication** uniquement côté Flutter Web.
Aucune API backend existante n'a été modifiée.

## Objectif

Flow utilisateur conservé :

1. `/login` : email + mot de passe Solola.
2. Firebase Auth vérifie que l'email existe et que `emailVerified == true`.
3. Si l'email n'est pas vérifié : redirection vers `/verify-email`.
4. Après vérification Firebase : retour au flow backend existant `/auth/login/start`.
5. `/verify-code` : saisie du code OTP backend Solola.
6. Connexion finale via `/auth/login/verify`.

Flow administrateur conservé :

1. `/admin/login` : email admin + mot de passe.
2. Firebase Auth vérifie l'email admin.
3. Si l'email n'est pas vérifié : `/verify-email`.
4. Puis OTP admin backend existant : `/admin/login/start` et `/admin/login/verify`.

## Important

Cette couche ne remplace pas la sécurité backend. Elle bloque l'interface si l'email Firebase n'est pas vérifié, mais le backend doit rester l'autorité de sécurité pour les rôles, tokens et permissions.

## Variables Netlify à ajouter

Dans Netlify > Site settings > Environment variables :

```env
API_BASE_URL=https://solola-backend.onrender.com
FIREBASE_AUTH_ENABLED=true
FIREBASE_API_KEY=...
FIREBASE_AUTH_DOMAIN=...
FIREBASE_PROJECT_ID=...
FIREBASE_STORAGE_BUCKET=...
FIREBASE_MESSAGING_SENDER_ID=...
FIREBASE_APP_ID=...
```

Si `FIREBASE_AUTH_ENABLED=false`, l'application conserve le flow backend existant sans vérification Firebase.

## Firebase Console

Dans Firebase Console :

1. Créer un projet Firebase.
2. Aller dans Authentication > Sign-in method.
3. Activer Email/Password.
4. Ajouter le domaine Netlify dans Authentication > Settings > Authorized domains.
5. Copier la configuration Web dans les variables Netlify.

## Fichiers ajoutés

```text
frontend_flutter/lib/firebase/config.dart
frontend_flutter/lib/services/firebase_email_verification_service.dart
frontend_flutter/lib/pages/verify_email_page.dart
README_FIREBASE_EMAIL_VERIFICATION.md
```

## Fichiers modifiés

```text
frontend_flutter/pubspec.yaml
frontend_flutter/lib/main.dart
frontend_flutter/lib/app.dart
frontend_flutter/lib/pages/auth_page.dart
frontend_flutter/lib/pages/admin_pages.dart
frontend_flutter/lib/pages/verify_code_page.dart
frontend_flutter/.env.example
netlify.toml
```

## Backend

Aucun fichier backend n'a été modifié pour cette couche Firebase.
