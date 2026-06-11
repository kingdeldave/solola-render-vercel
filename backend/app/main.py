"""Point d'entrée FastAPI de Solola.

Le fichier reste volontairement court. Toute la logique existante est chargée
par `app_runtime.py` afin de conserver le fonctionnement validé tout en ayant
une architecture de projet plus lisible.
"""

from app.app_runtime import app
