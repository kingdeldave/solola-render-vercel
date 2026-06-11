part of solola_app;

Future<String?> textDialog(
  BuildContext context, {
  required String title,
  required String label,
  bool obscure = false,
  bool requiredValue = true,
}) {
  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (requiredValue && controller.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

Future<Map<String, String>?> temporarySecureDialog(BuildContext context) {
  final pinCtrl = TextEditingController();
  final hintCtrl = TextEditingController();

  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Chiffrement temporaire'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Plusieurs messages seront chiffrés jusqu’à désactivation.'),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            TextField(
              controller: hintCtrl,
              decoration: const InputDecoration(labelText: 'Indice'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (pinCtrl.text.isEmpty) return;
              Navigator.pop(dialogContext, {
                'pin': pinCtrl.text,
                'hint': hintCtrl.text.trim(),
                'mode': 'temporary_secure',
              });
            },
            child: const Text('Activer'),
          ),
        ],
      );
    },
  );
}

Future<Map<String, String>?> secureConversationDialog(BuildContext context) {
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final hintCtrl = TextEditingController();

  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Conversation sécurisée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Numéro'),
            ),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            TextField(
              controller: hintCtrl,
              decoration: const InputDecoration(labelText: 'Indice'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (phoneCtrl.text.trim().isEmpty || pinCtrl.text.isEmpty) return;
              Navigator.pop(dialogContext, {
                'phone': phoneCtrl.text.trim(),
                'pin': pinCtrl.text,
                'hint': hintCtrl.text.trim(),
              });
            },
            child: const Text('Créer'),
          ),
        ],
      );
    },
  );
}

Future<Map<String, dynamic>?> groupDialog(BuildContext context, {required bool secure}) {
  final titleCtrl = TextEditingController();
  final membersCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final hintCtrl = TextEditingController();

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(secure ? 'Groupe sécurisé' : 'Nouveau groupe'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Nom du groupe'),
              ),
              TextField(
                controller: membersCtrl,
                decoration: const InputDecoration(labelText: 'Numéros séparés par virgule'),
              ),
              if (secure)
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'PIN'),
                ),
              if (secure)
                TextField(
                  controller: hintCtrl,
                  decoration: const InputDecoration(labelText: 'Indice'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              if (secure && pinCtrl.text.isEmpty) return;

              Navigator.pop(dialogContext, {
                'title': titleCtrl.text.trim(),
                'member_phone_numbers': membersCtrl.text
                    .split(',')
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(),
                if (secure) 'is_secure': true,
                if (secure) 'security_hint': hintCtrl.text.trim(),
                if (secure) 'pin': pinCtrl.text,
              });
            },
            child: const Text('Créer'),
          ),
        ],
      );
    },
  );
}
