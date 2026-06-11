part of solola_app;

class FirebaseEmailVerificationResult {
  final bool emailVerified;
  final bool newlyCreated;
  final String message;

  const FirebaseEmailVerificationResult({
    required this.emailVerified,
    required this.newlyCreated,
    required this.message,
  });
}

/// Couche frontend Firebase Auth.
/// Elle ne remplace pas l'authentification backend Solola : elle ajoute seulement
/// une vérification email avant de déclencher le flow OTP backend existant.
class FirebaseEmailVerificationService {
  FirebaseEmailVerificationService._();

  static bool _initialized = false;
  static String? _initializationError;

  static bool get enabled => kFirebaseAuthEnabled;
  static bool get initialized => _initialized;
  static String? get initializationError => _initializationError;

  static Future<void> initialize() async {
    if (!enabled) return;

    final options = buildFirebaseOptions();
    if (options == null) {
      _initializationError = 'Firebase Auth est activé, mais la configuration Firebase est incomplète.';
      debugPrint(_initializationError);
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      _initialized = true;
    } catch (e) {
      _initializationError = 'Impossible d’initialiser Firebase Auth : $e';
      debugPrint(_initializationError);
    }
  }

  static void _ensureReady() {
    if (!enabled) return;
    if (!_initialized) {
      throw Exception(_initializationError ?? 'Firebase Auth n’est pas initialisé.');
    }
  }

  static Future<FirebaseEmailVerificationResult> authenticateOrCreateAndCheck({
    required String email,
    required String password,
  }) async {
    if (!enabled) {
      return const FirebaseEmailVerificationResult(
        emailVerified: true,
        newlyCreated: false,
        message: 'Firebase Auth désactivé : flow backend conservé.',
      );
    }

    _ensureReady();

    UserCredential credential;
    bool newlyCreated = false;

    try {
      credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          newlyCreated = true;
        } on FirebaseAuthException catch (createError) {
          if (createError.code == 'email-already-in-use') {
            throw Exception('Compte Firebase existant : vérifie le mot de passe utilisé pour cet email.');
          }
          throw Exception(_friendlyFirebaseError(createError));
        }
      } else {
        throw Exception(_friendlyFirebaseError(e));
      }
    }

    var user = credential.user;
    if (user == null) {
      throw Exception('Session Firebase introuvable.');
    }

    await user.reload();
    user = FirebaseAuth.instance.currentUser ?? user;

    if (!user.emailVerified) {
      await sendVerificationEmail();
      return FirebaseEmailVerificationResult(
        emailVerified: false,
        newlyCreated: newlyCreated,
        message: newlyCreated
            ? 'Compte Firebase créé. Email de vérification envoyé.'
            : 'Email non vérifié. Nouveau lien de vérification envoyé.',
      );
    }

    return const FirebaseEmailVerificationResult(
      emailVerified: true,
      newlyCreated: false,
      message: 'Email Firebase vérifié.',
    );
  }

  static Future<void> sendVerificationEmail() async {
    if (!enabled) return;
    _ensureReady();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Aucun utilisateur Firebase connecté pour l’envoi de vérification.');
    }

    if (user.emailVerified) return;
    await user.sendEmailVerification();
  }

  static Future<bool> reloadAndCheckEmailVerified(String email) async {
    if (!enabled) return true;
    _ensureReady();

    var user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    if ((user.email ?? '').toLowerCase() != email.toLowerCase()) {
      return false;
    }

    await user.reload();
    user = FirebaseAuth.instance.currentUser;

    return user?.emailVerified == true;
  }

  static Future<void> signOut() async {
    if (!enabled || !_initialized) return;
    await FirebaseAuth.instance.signOut();
  }

  static String _friendlyFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Adresse email Firebase invalide.';
      case 'weak-password':
        return 'Mot de passe Firebase trop faible. Utilise au moins 6 caractères.';
      case 'wrong-password':
        return 'Mot de passe Firebase incorrect.';
      case 'too-many-requests':
        return 'Trop de tentatives Firebase. Réessaie plus tard.';
      case 'network-request-failed':
        return 'Connexion Firebase impossible. Vérifie Internet.';
      case 'operation-not-allowed':
        return 'Connexion email/mot de passe non activée dans Firebase Authentication.';
      default:
        return e.message ?? 'Erreur Firebase Auth : ${e.code}';
    }
  }
}
