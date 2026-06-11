part of solola_app;

class AuthVerifyRequest {
  final ApiClient api;
  final String email;
  final String password;
  final String channel;
  final bool admin;
  final String? destination;
  final Future<void> Function(String, Map<String, dynamic>)? onAuthenticated;

  const AuthVerifyRequest({
    required this.api,
    required this.email,
    required this.password,
    required this.channel,
    required this.admin,
    required this.destination,
    required this.onAuthenticated,
  });

  AuthVerifyRequest copyWith({String? destination}) {
    return AuthVerifyRequest(
      api: api,
      email: email,
      password: password,
      channel: channel,
      admin: admin,
      destination: destination ?? this.destination,
      onAuthenticated: onAuthenticated,
    );
  }
}

class VerifyCodePage extends StatefulWidget {
  final AuthVerifyRequest? pending;

  const VerifyCodePage({super.key, required this.pending});

  @override
  State<VerifyCodePage> createState() => _VerifyCodePageState();
}

class _VerifyCodePageState extends State<VerifyCodePage> {
  final codeCtrl = TextEditingController();
  bool busy = false;
  bool resendBusy = false;
  String? error;
  String? info;

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    final pending = widget.pending;
    if (pending == null) return;

    setState(() {
      busy = true;
      error = null;
      info = null;
    });

    try {
      final endpoint = pending.admin ? '/admin/login/verify' : '/auth/login/verify';
      final data = await pending.api.post(endpoint, {
        'email': pending.email,
        'code': codeCtrl.text.trim(),
      });

      final token = '${data['access_token']}';
      final user = Map<String, dynamic>.from(data['user']);

      if (pending.admin) {
        AdminSession.instance.open(accessToken: token, user: user);
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/admin', (_) => false);
        return;
      }

      final onAuthenticated = pending.onAuthenticated;
      if (onAuthenticated != null) {
        await onAuthenticated(token, user);
      }

      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    final pending = widget.pending;
    if (pending == null) return;

    setState(() {
      resendBusy = true;
      error = null;
      info = null;
    });

    try {
      final endpoint = pending.admin ? '/admin/login/start' : '/auth/login/start';
      final data = await pending.api.post(endpoint, {
        'email': pending.email,
        'password': pending.password,
        'channel': pending.channel,
      });

      setState(() {
        info = 'Nouveau code envoyé à ${data['destination'] ?? 'la destination choisie'}.';
      });
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => resendBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pending;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.55, -0.65),
            radius: 1.25,
            colors: [
              Color(0xFF043448),
              Color(0xFF061126),
              Color(0xFF160B34),
              Color(0xFF070817),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: pending == null ? _missingSession(context) : _verifyForm(pending),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _missingSession(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_clock_outlined, size: 56, color: Color(0xFF2563EB)),
        const SizedBox(height: 16),
        const Text('Aucune vérification en cours', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Reprends la connexion pour recevoir un nouveau code.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
          child: const Text('Retour à la connexion'),
        ),
      ],
    );
  }

  Widget _verifyForm(AuthVerifyRequest pending) {
    final destination = pending.destination?.isNotEmpty == true ? pending.destination! : 'la destination choisie';
    final title = pending.admin ? 'Vérification administrateur' : 'Vérification de connexion';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(pending.admin ? Icons.admin_panel_settings_outlined : Icons.verified_user_outlined, size: 58, color: const Color(0xFF2563EB)),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          'Entre le code à 6 chiffres envoyé à $destination. Le code expire après quelques minutes.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF475569), height: 1.35),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
          decoration: const InputDecoration(
            labelText: 'Code à 6 chiffres',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onSubmitted: (_) => busy ? null : verify(),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          _messageBox(error!, error: true),
        ],
        if (info != null) ...[
          const SizedBox(height: 14),
          _messageBox(info!, error: false),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : verify,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Vérifier'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: resendBusy ? null : resend,
          icon: resendBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: const Text('Renvoyer le code'),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, pending.admin ? '/admin/login' : '/login', (_) => false),
          child: const Text('Changer de compte'),
        ),
      ],
    );
  }

  Widget _messageBox(String text, {required bool error}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: error ? const Color(0xFF991B1B) : const Color(0xFF166534),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
