part of solola_app;

/// Session admin gardée uniquement en mémoire.
/// Aucun token admin n'est stocké dans SharedPreferences/localStorage.
class AdminSession {
  AdminSession._();

  static final AdminSession instance = AdminSession._();

  String? token;
  Map<String, dynamic>? adminUser;

  bool get isAuthenticated => token != null && adminUser != null && tokenLooksValid;
  String get role => '${adminUser?['role'] ?? ''}'.toUpperCase();

  bool get tokenLooksValid {
    try {
      final raw = token;
      if (raw == null || !raw.contains('.')) return false;

      final body = raw.split('.').first;
      final normalized = base64Url.normalize(body);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
      final exp = int.tryParse('${payload['exp'] ?? 0}') ?? 0;

      return exp > DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return false;
    }
  }

  void open({required String accessToken, required Map<String, dynamic> user}) {
    token = accessToken;
    adminUser = user;
  }

  void close() {
    token = null;
    adminUser = null;
  }
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final api = ApiClient(baseUrl: kDefaultApiBaseUrl, token: null);

  bool busy = false;
  bool obscurePassword = true;
  String deliveryChannel = 'email';
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> requestAdminCode() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final email = emailCtrl.text.trim().toLowerCase();
      final password = passwordCtrl.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email administrateur et mot de passe obligatoires.');
      }

      final pending = AuthVerifyRequest(
        api: api,
        email: email,
        password: password,
        channel: deliveryChannel,
        admin: true,
        destination: null,
        onAuthenticated: null,
      );

      final firebaseResult = await FirebaseEmailVerificationService.authenticateOrCreateAndCheck(
        email: email,
        password: password,
      );

      if (!firebaseResult.emailVerified) {
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          '/verify-email',
          arguments: EmailVerificationRequest(
            backendRequest: pending,
            newlyCreated: firebaseResult.newlyCreated,
            message: firebaseResult.message,
          ),
        );
        return;
      }

      await startBackendAdminOtp(pending);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startBackendAdminOtp(AuthVerifyRequest pending) async {
    final data = await api.post('/admin/login/start', {
      'email': pending.email,
      'password': pending.password,
      'channel': pending.channel,
    });

    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/verify-code',
      arguments: pending.copyWith(destination: '${data['destination'] ?? ''}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.55, -0.65),
            radius: 1.25,
            colors: [
              Color(0xFF0B3B54),
              Color(0xFF061126),
              Color(0xFF140B34),
              Color(0xFF050714),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 0,
                color: Colors.white.withOpacity(0.96),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: const [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Color(0xFF0F172A),
                            child: Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Administration Solola', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                                SizedBox(height: 4),
                                Text('Accès réservé aux administrateurs. Une vérification OTP est obligatoire.', style: TextStyle(color: Color(0xFF475569))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email administrateur',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe admin',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                            icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        onSubmitted: (_) => busy ? null : requestAdminCode(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Recevoir le code par :', style: TextStyle(fontWeight: FontWeight.w900)),
                      RadioListTile<String>(
                        value: 'email',
                        groupValue: deliveryChannel,
                        onChanged: busy ? null : (value) => setState(() => deliveryChannel = value ?? 'email'),
                        title: const Text('Email'),
                      ),
                      RadioListTile<String>(
                        value: 'sms',
                        groupValue: deliveryChannel,
                        onChanged: busy ? null : (value) => setState(() => deliveryChannel = value ?? 'sms'),
                        title: const Text('SMS'),
                        subtitle: const Text('Envoyé au numéro enregistré du compte admin'),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(error!, style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w700)),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: busy ? null : requestAdminCode,
                        icon: busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.security_outlined),
                        label: const Text('Recevoir le code admin'),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Retour connexion utilisateur'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final ApiClient api;
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    api = ApiClient(baseUrl: kDefaultApiBaseUrl, token: AdminSession.instance.token);
    future = load();
  }

  Future<Map<String, dynamic>> load() async {
    final me = await api.get('/admin/me');
    final settings = await api.get('/admin/settings');
    return {
      'me': Map<String, dynamic>.from(me),
      'settings': Map<String, dynamic>.from(settings),
    };
  }

  Future<void> logoutAdmin() async {
    AdminSession.instance.close();
    await FirebaseEmailVerificationService.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/admin/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FF),
      appBar: AppBar(
        title: const Text('Solola Admin'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/admin/settings'),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Paramètres'),
          ),
          IconButton(onPressed: logoutAdmin, icon: const Icon(Icons.logout)),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'.replaceFirst('Exception: ', '')));
          }

          final data = snapshot.data ?? {};
          final me = Map<String, dynamic>.from(data['me'] ?? {});
          final settings = Map<String, dynamic>.from(data['settings'] ?? {});

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _adminHero(me),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  AdminStatCard(label: 'Rôle', value: '${me['role'] ?? 'ADMIN'}', icon: Icons.verified_user_outlined),
                  AdminStatCard(label: 'Backend', value: kDefaultApiBaseUrl, icon: Icons.cloud_done_outlined),
                  AdminStatCard(label: 'OTP démo', value: '${settings['otp_demo_mode'] ?? false}', icon: Icons.sms_outlined),
                ],
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Contrôles système', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      SizedBox(height: 8),
                      Text('Cet espace est séparé des paramètres utilisateur. Les utilisateurs normaux ne voient jamais ces options.'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _adminHero(Map<String, dynamic> me) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061126), Color(0xFF1238B5), Color(0xFF4C1D95)],
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 34, child: Icon(Icons.admin_panel_settings_outlined, size: 34)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${me['pseudo'] ?? 'Administrateur'}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('${me['phone_number'] ?? ''}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminSettings extends StatefulWidget {
  const AdminSettings({super.key});

  @override
  State<AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings> {
  late final ApiClient api;
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    api = ApiClient(baseUrl: kDefaultApiBaseUrl, token: AdminSession.instance.token);
    future = api.get('/admin/settings').then((value) => Map<String, dynamic>.from(value));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FF),
      appBar: AppBar(
        title: const Text('Paramètres administrateur'),
        leading: IconButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/admin', (_) => false),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'.replaceFirst('Exception: ', '')));
          }

          final settings = snapshot.data ?? {};

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Configuration système', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      _readonlyLine('API backend', kDefaultApiBaseUrl),
                      _readonlyLine('Origine frontend', '${settings['frontend_origin'] ?? ''}'),
                      _readonlyLine('Origine tracking', '${settings['tracking_origin'] ?? ''}'),
                      _readonlyLine('Mode OTP démo', '${settings['otp_demo_mode'] ?? false}'),
                      _readonlyLine('SMTP configuré', '${settings['smtp_configured'] ?? false}'),
                      _readonlyLine('Canal SMS', '${settings['sms_provider'] ?? 'console'}'),
                      _readonlyLine('Upload max', '${settings['max_upload_mb'] ?? ''} Mo'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Règles', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      SizedBox(height: 8),
                      Text('Les secrets serveur, les clés OTP/SMS et le code tracking ne doivent jamais être exposés côté Flutter.'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _readonlyLine(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
      subtitle: Text(value.isEmpty ? 'Non défini' : value, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const AdminStatCard({super.key, required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
