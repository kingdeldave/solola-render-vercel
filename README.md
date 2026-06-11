# Solola Flutter Secure V25 - Architecture structurée

Cette version restructure le projet en fichiers séparés : SQL, backend runtime, frontend pages, widgets, services et documentation.

## Lancer le backend

```bat
cd /d "D:\solola_flutter_secure_v25_architecture\backend"
start_backend.bat
```

Vérifier :

```txt
http://localhost:8000/docs
```

## Lancer le frontend

```bat
cd /d "D:\solola_flutter_secure_v25_architecture\frontend_flutter"
flutter clean
flutter pub get
flutter run -d edge
```

## Structure importante

```txt
backend/app/sql/schema.sql
backend/app/main.py
backend/app/app_runtime.py
frontend_flutter/lib/main.dart
frontend_flutter/lib/app.dart
frontend_flutter/lib/pages/
frontend_flutter/lib/widgets/
frontend_flutter/lib/services/
docs/
```
