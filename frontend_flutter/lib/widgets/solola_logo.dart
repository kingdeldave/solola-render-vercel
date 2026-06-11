part of solola_app;

class SololaLogo extends StatelessWidget {
  final String logoUrl;
  final double size;
  final bool showText;

  const SololaLogo({
    super.key,
    required this.logoUrl,
    this.size = 64,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.trim().isNotEmpty
          ? Image.network(
              logoUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset('assets/images/solola_logo.png', fit: BoxFit.cover),
            )
          : Image.asset('assets/images/solola_logo.png', fit: BoxFit.cover),
    );

    if (!showText) return logo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 16),
        const Text(
          'SOLOLA',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'COMMUNIQUER • CONNECTER • PARTAGER',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w800,
            color: Color(0xFFEAF4FF),
          ),
        ),
      ],
    );
  }
}

/// Page de connexion / inscription OTP gratuite.
