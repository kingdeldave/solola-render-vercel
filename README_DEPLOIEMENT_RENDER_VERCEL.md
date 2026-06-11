# Déploiement Solola : backend Render + frontend Vercel

## Backend Render

Le backend FastAPI est dans le dossier `backend/`.

Réglages Render à utiliser :

```text
Root Directory: backend
Build Command: pip install -r requirements.txt
Start Command: uvicorn app.main:app --host 0.0.0.0 --port $PORT
Health Check Path: /
```

Variables d'environnement Render :

```text
SECRET_KEY=<générer une longue valeur secrète>
DATABASE_PATH=solola.db
ADMIN_CODE=<code admin de ton choix>
```

Après déploiement, tester :

```text
https://TON-BACKEND.onrender.com/
```

## Frontend Vercel

Le frontend Flutter est dans le dossier `frontend_flutter/`.

Réglages Vercel :

```text
Root Directory: frontend_flutter
Framework Preset: Other
Install Command: git clone https://github.com/flutter/flutter.git -b stable --depth 1 && ./flutter/bin/flutter config --enable-web && ./flutter/bin/flutter pub get
Build Command: ./flutter/bin/flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL
Output Directory: build/web
```

Variable d'environnement Vercel :

```text
API_BASE_URL=https://TON-BACKEND.onrender.com
```

## Déploiement local vers Vercel, méthode alternative

Depuis `frontend_flutter/` :

```powershell
flutter clean
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://TON-BACKEND.onrender.com
cd build/web
vercel --prod
```

## Attention SQLite sur Render gratuit

Ce projet utilise SQLite et un dossier `uploads/`. Sur Render gratuit, ces fichiers locaux peuvent être perdus après redémarrage ou redéploiement. Pour une vraie production, il faut migrer vers PostgreSQL et un stockage de fichiers externe.
