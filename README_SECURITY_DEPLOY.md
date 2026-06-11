# Solola - Corrections sécurité et séparation tracking

## Ce qui a été modifié

1. Le mode démo OTP n'est plus affiché dans Flutter.
2. Le backend ne renvoie plus `dev_code`, sauf si `OTP_DEMO_MODE=true`.
3. Le code tracking n'est plus accessible depuis l'application principale Flutter.
4. Une application séparée a été ajoutée dans `tracking_admin/`.
5. Le dashboard tracking a été refait en mode SOC/admin.
6. Le CORS backend est restreint avec `FRONTEND_ORIGIN` et `TRACKING_ORIGIN`.
7. Le code admin `1234` a été supprimé des exemples.
8. Les tokens tracking expirent après 2 heures.
9. Les tentatives OTP et tracking login sont limitées en mémoire.
10. Les uploads sont limités avec `MAX_UPLOAD_MB`.
11. Les fichiers de conversation sont protégés par authentification et appartenance à la conversation.
12. Des headers HTTP de sécurité ont été ajoutés côté backend et Netlify.

## Variables Render recommandées

```env
APP_ENV=production
SECRET_KEY=une-valeur-longue-aleatoire-de-32-caracteres-minimum
DATABASE_PATH=solola.db
ADMIN_CODE=un-code-admin-long-non-devinable
FRONTEND_ORIGIN=https://solola-front.netlify.app
TRACKING_ORIGIN=https://ton-tracking-admin.netlify.app
OTP_DEMO_MODE=true
MAX_UPLOAD_MB=10
```

Pour une vraie production, remplacer `OTP_DEMO_MODE=true` par `false` et brancher un fournisseur email/SMS dans `deliver_otp()`.

## Déploiement frontend principal Netlify

- Base directory : `frontend_flutter`
- Build command : déjà dans `netlify.toml`
- Publish directory : `build/web`

## Déploiement tracking séparé Netlify

Créer un deuxième site Netlify avec :

- Base directory : `tracking_admin`
- Build command : vide
- Publish directory : `.`

Puis mettre son URL dans Render :

```env
TRACKING_ORIGIN=https://ton-tracking-admin.netlify.app
```

## Important

SQLite et les fichiers locaux Render restent adaptés au TP, pas à la production. Pour production, migrer vers PostgreSQL et stockage cloud.
