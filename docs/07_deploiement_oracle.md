# Déploiement Oracle

Architecture recommandée :

- VM Oracle Always Free Ubuntu.
- FastAPI lancé via systemd.
- Nginx pour servir Flutter Web et rediriger l'API.
- SQLite et uploads stockés sur le disque de la VM.
