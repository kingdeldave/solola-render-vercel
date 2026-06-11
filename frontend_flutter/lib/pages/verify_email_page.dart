part of solola_app;

class EmailVerificationRequest {
  final AuthVerifyRequest backendRequest;
  final bool newlyCreated;
  final String message;

  const EmailVerificationRequest({
    required this.backendRequest,
    required this.newlyCreated,
    required this.message,
  });
}

class VerifyEmailPage extends StatefulWidget {
  final EmailVerificationRequest? pending;

  const VerifyEmailPage({super.key, required this.pending});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool busy = false;
  bool resendBusy = false;
  String? error;
  String? info;

  Future<void> resendEmail() async {
    final pending = widget.pending;
    if (pending == null) return;

    setState(() {
      resendBusy = true;
      error = null;
      info = null;
    });

    try {
      await FirebaseEmailVerificationService.sendVerificationEmail();
      setState(() => info = 'Email de vérification renvoyé à ${pending.backendRequest.email}.');
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => resendBusy = false);
    }
  }

  Future<void> continueAfterVerification() async {
    final pending = widget.pending;
    if (pending == null) return;

    setState(() {
      busy = true;
      error = null;
      info = null;
    });

    try {
      final verified = await FirebaseEmailVerificationService.reloadAndCheckEmailVerified(
        pending.backendRequest.email,
      );

      if (!verified) {
        throw Exception('Email pas encore vérifié. Ouvre le lien reçu par email, puis réessaie.');
      }

      final endpoint = pending.backendRequest.admin ? '/admin/login/start' : '/auth/login/start';
      final data = await pending.backendRequest.api.post(endpoint, {
        'email': pending.backendRequest.email,
        'password': pending.backendRequest.password,
        'channel': pending.backendRequest.channel,
      });

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/verify-code',
        arguments: pending.backendRequest.copyWith(destination: '${data['destination'] ?? ''}'),
      );
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
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
              constraints: const BoxConstraints(maxWidth: 540),
              child: Card(
                elevation: 0,
                color: Colors.white.withOpacity(0.97),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: pending == null ? _missingSession(context) : _verifyEmailForm(pending),
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
        const Icon(Icons.mark_email_unread_outlined, size: 58, color: Color(0xFF2563EB)),
        const SizedBox(height: 16),
        const Text('Aucune vérification email en cours', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Reprends la connexion pour recevoir un email de vérification.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
          child: const Text('Retour à la connexion'),
        ),
      ],
    );
  }

  Widget _verifyEmailForm(EmailVerificationRequest pending) {
    final email = pending.backendRequest.email;
    final title = pending.backendRequest.admin ? 'Vérification email administrateur' : 'Vérifiez votre email';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: Color(0xFF2563EB)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text(
          'Un email de vérification Firebase a été envoyé à $email. Ouvre le lien reçu, puis reviens ici.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF475569), height: 1.4),
        ),
        if (pending.message.isNotEmpty) ...[
          const SizedBox(height: 14),
          _messageBox(pending.message, error: false),
        ],
        if (error != null) ...[
          const SizedBox(height: 14),
          _messageBox(error!, error: true),
        ],
        if (info != null) ...[
          const SizedBox(height: 14),
          _messageBox(info!, error: false),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: busy ? null : continueAfterVerification,
          icon: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.verified_outlined),
          label: const Text('J’ai vérifié'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: resendBusy ? null : resendEmail,
          icon: resendBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: const Text('Renvoyer l’email'),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            pending.backendRequest.admin ? '/admin/login' : '/login',
            (_) => false,
          ),
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
