part of solola_app;

/// URL backend par défaut.
/// En production Vercel, cette valeur est injectée avec :
/// flutter build web --dart-define=API_BASE_URL=https://ton-backend.onrender.com
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://solola-backend.onrender.com',
);

class SololaApp extends StatefulWidget {
  const SololaApp({super.key});

  @override
  State<SololaApp> createState() => _SololaAppState();
}

class _SololaAppState extends State<SololaApp> {
  Color seedColor = const Color(0xFF2563EB);
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    restoreTheme();
  }

  Future<void> restoreTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      seedColor = Color(prefs.getInt('solola_theme_color') ?? 0xFF2563EB);
      darkMode = prefs.getBool('solola_dark_mode') ?? false;
    });
  }

  Future<void> changeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('solola_theme_color', color.value);
    setState(() => seedColor = color);
  }

  Future<void> changeDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('solola_dark_mode', value);
    setState(() => darkMode = value);
  }

  String initialRoute() {
    final path = Uri.base.path;

    if (path == '/admin/login') return '/admin/login';
    if (path == '/admin/settings') return '/admin/settings';
    if (path.startsWith('/admin')) return '/admin';
    if (path == '/settings') return '/settings';
    if (path == '/verify-code') return '/verify-code';
    if (path == '/verify-email') return '/verify-email';
    if (path == '/login') return '/login';

    return '/login';
  }

  Route<dynamic> buildRoute(RouteSettings settings) {
    Widget page;

    switch (settings.name) {
      case '/admin/login':
        page = const AdminLoginPage();
        break;
      case '/admin':
        page = const AdminProtectedRoute(child: AdminDashboard());
        break;
      case '/admin/settings':
        page = const AdminProtectedRoute(child: AdminSettings());
        break;
      case '/verify-code':
        page = VerifyCodePage(pending: settings.arguments is AuthVerifyRequest ? settings.arguments as AuthVerifyRequest : null);
        break;
      case '/verify-email':
        page = VerifyEmailPage(pending: settings.arguments is EmailVerificationRequest ? settings.arguments as EmailVerificationRequest : null);
        break;
      case '/settings':
        page = RootPage(
          initialSection: AppSection.settings,
          darkMode: darkMode,
          onDarkModeChanged: changeDarkMode,
          onColorChanged: changeColor,
        );
        break;
      case '/login':
      case '/':
      default:
        page = RootPage(
          darkMode: darkMode,
          onDarkModeChanged: changeDarkMode,
          onColorChanged: changeColor,
        );
    }

    return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solola',
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute(),
      onGenerateRoute: buildRoute,
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        scaffoldBackgroundColor: const Color(0xFFF3F7FF),
        cardTheme: const CardThemeData(elevation: 0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
      ),
    );
  }
}

/// Client HTTP pour communiquer avec le backend FastAPI.

class RootPage extends StatefulWidget {
  final AppSection? initialSection;
  final bool darkMode;
  final Future<void> Function(bool) onDarkModeChanged;
  final Future<void> Function(Color) onColorChanged;

  const RootPage({
    super.key,
    this.initialSection,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onColorChanged,
  });

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  late ApiClient api;
  Map<String, dynamic>? user;
  String logoUrl = '';
  String? runtimeToken;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = kDefaultApiBaseUrl;
    final userJson = prefs.getString('solola_user');
    logoUrl = prefs.getString('solola_logo_url') ?? '';

    // Sécurité Web : le token JWT n'est pas restauré depuis le stockage navigateur.
    // L'utilisateur devra se reconnecter après un rechargement complet de la page.
    runtimeToken = null;
    api = ApiClient(baseUrl: apiUrl, token: runtimeToken);

    if (userJson != null && runtimeToken != null) {
      user = Map<String, dynamic>.from(jsonDecode(userJson));
    }

    setState(() => loading = false);
  }

  Future<void> setApiUrl(String value) async {
    // En production, l'URL API est fixée au build avec API_BASE_URL.
    // On évite qu'un utilisateur connecte l'application à un faux backend.
    api.baseUrl = kDefaultApiBaseUrl;
  }

  Future<void> setLogoUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('solola_logo_url', value.trim());
    setState(() => logoUrl = value.trim());
  }

  Future<void> setAuthenticatedUser(String token, Map<String, dynamic> nextUser) async {
    final prefs = await SharedPreferences.getInstance();
    // Ne pas stocker le token dans SharedPreferences sur Flutter Web.
    // SharedPreferences Web correspond à un stockage navigateur persistant.
    runtimeToken = token;
    await prefs.setString('solola_user', jsonEncode(nextUser));

    api.token = runtimeToken;
    setState(() => user = nextUser);
  }

  Future<void> updateUser(Map<String, dynamic> nextUser) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('solola_user', jsonEncode(nextUser));
    setState(() => user = nextUser);
  }

  Future<void> logout() async {
    await FirebaseEmailVerificationService.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('solola_token');
    await prefs.remove('solola_user');

    runtimeToken = null;
    api.token = null;
    setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user == null) {
      return AuthPage(
        api: api,
        logoUrl: logoUrl,
        onAuthenticated: setAuthenticatedUser,
      );
    }

    return HomePage(
      api: api,
      user: user!,
      logoUrl: logoUrl,
      initialSection: widget.initialSection,
      updateUser: updateUser,
      logout: logout,
      darkMode: widget.darkMode,
      onDarkModeChanged: widget.onDarkModeChanged,
      onColorChanged: widget.onColorChanged,
    );
  }
}

/// Logo réutilisable de Solola.
/// Il utilise l'asset local `assets/images/solola_logo.png`.
