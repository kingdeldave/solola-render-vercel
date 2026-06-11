part of solola_app;

class AuthPage extends StatefulWidget {
  final ApiClient api;
  final String logoUrl;
  final Future<void> Function(String, Map<String, dynamic>) onAuthenticated;

  const AuthPage({
    super.key,
    required this.api,
    required this.logoUrl,
    required this.onAuthenticated,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  // Ancien flow conservé : OTP par téléphone sans mot de passe.
  final phoneCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  final pseudoCtrl = TextEditingController();

  bool legacyPhoneMode = false;
  bool phoneCodeSent = false;
  bool isNewUser = false;
  bool busy = false;
  bool obscurePassword = true;
  String deliveryChannel = 'email';
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    phoneCtrl.dispose();
    codeCtrl.dispose();
    pseudoCtrl.dispose();
    super.dispose();
  }

  Future<void> requestEmailLoginCode() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final email = emailCtrl.text.trim().toLowerCase();
      final password = passwordCtrl.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email et mot de passe obligatoires.');
      }

      final pending = AuthVerifyRequest(
        api: widget.api,
        email: email,
        password: password,
        channel: deliveryChannel,
        admin: false,
        destination: null,
        onAuthenticated: widget.onAuthenticated,
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

      await startBackendOtp(pending);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startBackendOtp(AuthVerifyRequest pending) async {
    final data = await widget.api.post('/auth/login/start', {
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

  Future<void> requestLegacyPhoneCode() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final phone = phoneCtrl.text.trim();
      if (phone.isEmpty) throw Exception('Entre ton numéro de téléphone.');

      final data = await widget.api.post('/auth/otp/start', {
        'phone_number': phone,
      });

      setState(() {
        phoneCodeSent = true;
        isNewUser = data['is_new_user'] == true;
      });
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyLegacyPhoneCode() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final phone = phoneCtrl.text.trim();
      final code = codeCtrl.text.trim();

      if (phone.isEmpty || code.isEmpty) {
        throw Exception('Numéro et code obligatoires.');
      }

      if (isNewUser && pseudoCtrl.text.trim().isEmpty) {
        throw Exception('Entre ton nom de profil.');
      }

      final data = await widget.api.post('/auth/otp/verify', {
        'phone_number': phone,
        'code': code,
        'pseudo': pseudoCtrl.text.trim(),
      });

      await widget.onAuthenticated(
        '${data['access_token']}',
        Map<String, dynamic>.from(data['user']),
      );
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void changePhoneNumber() {
    setState(() {
      phoneCodeSent = false;
      isNewUser = false;
      error = null;
      codeCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = legacyPhoneMode
        ? (phoneCodeSent ? 'Vérifie ton numéro' : 'Connexion par téléphone')
        : 'Connexion Solola';
    final subtitle = legacyPhoneMode
        ? (phoneCodeSent ? 'Entre le code reçu pour continuer.' : 'Ancien accès conservé par OTP téléphone.')
        : kFirebaseAuthEnabled
            ? 'Vérifie d’abord ton email Firebase, puis reçois le code OTP Solola.'
            : 'Entre ton email et ton mot de passe, puis choisis comment recevoir le code.';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.62, -0.55),
            radius: 1.35,
            colors: [
              Color(0xFF043448),
              Color(0xFF061126),
              Color(0xFF160B34),
              Color(0xFF070817),
            ],
            stops: [0.0, 0.34, 0.68, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 52,
                      offset: const Offset(0, 26),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(34, 36, 34, 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: SololaLogo(logoUrl: widget.logoUrl, size: 138, showText: true)),
                      const SizedBox(height: 28),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFD7E5F7), fontSize: 16, height: 1.35),
                      ),
                      const SizedBox(height: 28),
                      if (!legacyPhoneMode) _emailPasswordLogin() else _legacyPhoneLogin(),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE4E6).withOpacity(0.95),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFBE123C), fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  legacyPhoneMode = !legacyPhoneMode;
                                  error = null;
                                }),
                        child: Text(
                          legacyPhoneMode ? 'Utiliser email + mot de passe' : 'Ancien accès par numéro de téléphone',
                          style: const TextStyle(color: Color(0xFFBFC8FF), fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kFirebaseAuthEnabled
                            ? 'Firebase vérifie l’email côté frontend. Le code OTP reste vérifié par le backend Solola.'
                            : 'Le code est vérifié côté serveur. Aucun code secret n’est affiché dans le frontend.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Color(0xFFA8B6D3), height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/admin/login'),
                        icon: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF80DFFF)),
                        label: const Text('Connexion administrateur', style: TextStyle(color: Color(0xFF80DFFF))),
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

  Widget _emailPasswordLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DarkInput(
          controller: emailCtrl,
          label: 'Email',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _DarkInput(
          controller: passwordCtrl,
          label: 'Mot de passe',
          icon: Icons.lock_outline,
          obscure: obscurePassword,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => obscurePassword = !obscurePassword),
            icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: const Color(0xFFBFC8FF)),
            label: Text(obscurePassword ? 'Afficher' : 'Masquer', style: const TextStyle(color: Color(0xFFBFC8FF))),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Recevoir le code par :', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        _channelChoice(),
        const SizedBox(height: 16),
        _PrimaryGradientButton(
          text: 'Recevoir le code',
          loading: busy,
          onPressed: busy ? null : requestEmailLoginCode,
        ),
      ],
    );
  }

  Widget _channelChoice() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Column(
        children: [
          RadioListTile<String>(
            value: 'email',
            groupValue: deliveryChannel,
            onChanged: busy ? null : (value) => setState(() => deliveryChannel = value ?? 'email'),
            activeColor: const Color(0xFF39D5FF),
            title: const Text('Email', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          RadioListTile<String>(
            value: 'sms',
            groupValue: deliveryChannel,
            onChanged: busy ? null : (value) => setState(() => deliveryChannel = value ?? 'sms'),
            activeColor: const Color(0xFF39D5FF),
            title: const Text('SMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: const Text('Envoyé au numéro enregistré du compte', style: TextStyle(color: Color(0xFFB7C5DD))),
          ),
        ],
      ),
    );
  }

  Widget _legacyPhoneLogin() {
    if (!phoneCodeSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DarkInput(
            controller: phoneCtrl,
            label: 'Numéro de téléphone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _PrimaryGradientButton(
            text: 'Continuer',
            loading: busy,
            onPressed: busy ? null : requestLegacyPhoneCode,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : changePhoneNumber,
            icon: const Icon(Icons.arrow_back, color: Color(0xFF80DFFF)),
            label: Text(phoneCtrl.text.trim(), style: const TextStyle(color: Color(0xFF80DFFF), fontWeight: FontWeight.w800)),
          ),
        ),
        if (isNewUser) _DarkInput(controller: pseudoCtrl, label: 'Nom de profil', icon: Icons.person_outline),
        const SizedBox(height: 12),
        _DarkInput(
          controller: codeCtrl,
          label: 'Code de vérification',
          icon: Icons.verified_user_outlined,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        _PrimaryGradientButton(
          text: 'Vérifier et entrer',
          loading: busy,
          onPressed: busy ? null : verifyLegacyPhoneCode,
        ),
        TextButton(
          onPressed: busy ? null : requestLegacyPhoneCode,
          child: const Text('Renvoyer le code', style: TextStyle(color: Color(0xFFBFC8FF))),
        ),
      ],
    );
  }
}
