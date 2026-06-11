# Chiffrement

Solola utilise un chiffrement local par PIN côté Flutter :

- PBKDF2 pour dériver une clé depuis le PIN.
- AES-GCM pour chiffrer les messages.
- Le PIN n'est pas envoyé au serveur.
- Le serveur ne stocke que le texte chiffré.
