part of solola_app;

/// Guard réutilisable pour les routes protégées côté Flutter.
/// Important : ce guard améliore l'UX, mais la sécurité réelle reste côté backend.
class ProtectedRoute extends StatelessWidget {
  final Map<String, dynamic>? user;
  final List<String> allowedRoles;
  final Widget child;
  final Widget? fallback;

  const ProtectedRoute({
    super.key,
    required this.user,
    required this.allowedRoles,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return fallback ?? const AccessDeniedPage(message: 'Connexion requise.');
    }

    final role = '${user?['role'] ?? 'USER'}'.toUpperCase();
    final normalizedRoles = allowedRoles.map((item) => item.toUpperCase()).toSet();

    if (!normalizedRoles.contains(role)) {
      return const AccessDeniedPage(message: 'Accès refusé : rôle insuffisant.');
    }

    return child;
  }
}

/// Guard dédié aux pages d'administration Flutter.
class AdminProtectedRoute extends StatelessWidget {
  final Widget child;

  const AdminProtectedRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!AdminSession.instance.isAuthenticated) {
      return const AdminLoginPage();
    }

    if (AdminSession.instance.role != 'ADMIN') {
      return const AccessDeniedPage(message: 'Accès réservé aux administrateurs.');
    }

    return child;
  }
}

class AccessDeniedPage extends StatelessWidget {
  final String message;

  const AccessDeniedPage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF061126), Color(0xFF0F172A), Color(0xFF312E81)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 58, color: Color(0xFF2563EB)),
                    const SizedBox(height: 16),
                    const Text(
                      'Route protégée',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                      icon: const Icon(Icons.login),
                      label: const Text('Retour à la connexion'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
