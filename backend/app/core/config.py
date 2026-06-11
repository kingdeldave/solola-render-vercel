"""Configuration centrale de Solola.

La version runtime conserve la compatibilité dans `app_runtime.py`.
Ce fichier sert de point d'extension pour déplacer progressivement les variables
d'environnement hors du runtime principal.
"""

from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
STATIC_DIR = BASE_DIR / "static"
UPLOAD_DIR = BASE_DIR / "uploads"
