# Architecture Solola V25

Solola est organisé en deux couches principales :

- `backend/` : API FastAPI, SQLite, tracking, WebSocket et fichiers.
- `frontend_flutter/` : interface Flutter Web, authentification OTP, discussions, statuts et paramètres.

La version V25 sépare le frontend en fichiers Dart spécialisés et isole le SQL dans un fichier dédié.
Le backend conserve un runtime compatible (`app_runtime.py`) afin d'éviter de casser les routes déjà validées.
