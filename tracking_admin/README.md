# Solola Tracking Admin séparé

Ce dossier contient l'interface administrateur séparée de Solola.

Déploiement conseillé : Netlify Static Site.

Configuration Netlify :

- Base directory : `tracking_admin`
- Build command : laisser vide
- Publish directory : `.`

Le dashboard communique avec l'API Render via :

`https://solola-backend.onrender.com`

À configurer côté Render :

- `ADMIN_CODE` : code long, minimum 12 caractères
- `TRACKING_ORIGIN` : URL Netlify du dashboard tracking
- `FRONTEND_ORIGIN` : URL Netlify de l'application principale
