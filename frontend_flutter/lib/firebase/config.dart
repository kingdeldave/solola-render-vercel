part of solola_app;

/// Configuration Firebase Auth injectée au build Flutter avec --dart-define.
/// Aucune clé serveur ou secret backend ne doit être placé ici.
const bool kFirebaseAuthEnabled = bool.fromEnvironment(
  'FIREBASE_AUTH_ENABLED',
  defaultValue: false,
);

const String kFirebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const String kFirebaseAuthDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
const String kFirebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const String kFirebaseStorageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
const String kFirebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const String kFirebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');

FirebaseOptions? buildFirebaseOptions() {
  if (!kFirebaseAuthEnabled) return null;

  final requiredValues = [
    kFirebaseApiKey,
    kFirebaseAuthDomain,
    kFirebaseProjectId,
    kFirebaseMessagingSenderId,
    kFirebaseAppId,
  ];

  if (requiredValues.any((value) => value.trim().isEmpty)) {
    return null;
  }

  return const FirebaseOptions(
    apiKey: kFirebaseApiKey,
    authDomain: kFirebaseAuthDomain,
    projectId: kFirebaseProjectId,
    storageBucket: kFirebaseStorageBucket,
    messagingSenderId: kFirebaseMessagingSenderId,
    appId: kFirebaseAppId,
  );
}
