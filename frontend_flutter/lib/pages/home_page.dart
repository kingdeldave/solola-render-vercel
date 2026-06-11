part of solola_app;

class HomePage extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic> user;
  final String logoUrl;
  final AppSection? initialSection;
  final Future<void> Function(Map<String, dynamic>) updateUser;
  final Future<void> Function() logout;
  final bool darkMode;
  final Future<void> Function(bool) onDarkModeChanged;
  final Future<void> Function(Color) onColorChanged;

  const HomePage({
    super.key,
    required this.api,
    required this.user,
    required this.logoUrl,
    this.initialSection,
    required this.updateUser,
    required this.logout,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onColorChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late AppSection section;

  List<dynamic> conversations = [];
  List<dynamic> messages = [];
  List<dynamic> statuses = [];

  int? activeConversationId;
  bool groupsOnly = false;

  WebSocketChannel? socket;
  Timer? reconnectTimer;

  final messageCtrl = TextEditingController();
  final searchCtrl = TextEditingController();

  bool notifyMessages = true;
  bool notifyGroups = true;
  bool compactMode = false;

  final Map<int, String> decryptedMessages = {};
  final Map<int, String> securePins = {};
  final Map<int, Map<String, String>> temporarySecurity = {};
  final Map<int, int> unreadCounts = {};

  @override
  void initState() {
    super.initState();
    section = widget.initialSection ?? AppSection.chats;
    loadUserPreferences();
    loadAll();
    connectWebSocket();
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    socket?.sink.close();
    messageCtrl.dispose();
    searchCtrl.dispose();

    super.dispose();
  }

  Future<void> loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      notifyMessages = prefs.getBool('solola_notify_messages') ?? true;
      notifyGroups = prefs.getBool('solola_notify_groups') ?? true;
      compactMode = prefs.getBool('solola_compact_mode') ?? false;
    });
  }

  Future<void> saveNotificationPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);

    if (!mounted) return;

    setState(() {
      if (key == 'solola_notify_messages') notifyMessages = value;
      if (key == 'solola_notify_groups') notifyGroups = value;
      if (key == 'solola_compact_mode') compactMode = value;
    });
  }

  Future<void> loadAll() async {
    try {
      conversations = await widget.api.get('/conversations');
      statuses = uniqueStatusList(await widget.api.get('/statuses'));
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  List<dynamic> uniqueStatusList(dynamic rawStatuses) {
    final result = <dynamic>[];
    final seen = <String>{};

    for (final raw in (rawStatuses as List? ?? <dynamic>[])) {
      final status = Map<String, dynamic>.from(raw);
      final key = '${status['id'] ?? status['file']?['download_url'] ?? jsonEncode(status)}';
      if (seen.add(key)) result.add(status);
    }

    return result;
  }

  void upsertStatus(dynamic rawStatus) {
    final status = Map<String, dynamic>.from(rawStatus);
    final id = status['id'];
    final existingIndex = statuses.indexWhere((item) {
      final current = Map<String, dynamic>.from(item);
      return current['id'] == id;
    });

    if (existingIndex >= 0) {
      statuses[existingIndex] = status;
    } else {
      statuses.insert(0, status);
    }
  }

  Future<void> loadMessages(int conversationId) async {
    try {
      messages = await widget.api.get('/conversations/$conversationId/messages');
      unreadCounts[conversationId] = 0;
      if (mounted) setState(() {});
      await markConversationRead(conversationId);
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> refreshConversations() async {
    try {
      conversations = await widget.api.get('/conversations');
      if (mounted) setState(() {});
    } catch (_) {
      // On ignore pour éviter de bloquer l'interface pendant le temps réel.
    }
  }

  Future<void> markConversationRead(int conversationId) async {
    try {
      await widget.api.post('/conversations/$conversationId/read', {});
    } catch (_) {}
  }

  void connectWebSocket() {
    try {
      socket = WebSocketChannel.connect(Uri.parse(widget.api.websocketUrl()));
      socket!.sink.add(jsonEncode({'type': 'ping'}));

      socket!.stream.listen(
        (event) async {
          final data = jsonDecode(event.toString());

          if (data['type'] == 'new_message') {
            final message = data['payload'];
            final conversationId = message['conversation_id'];

            if (conversationId == activeConversationId) {
              if (!messages.any((item) => item['id'] == message['id'])) {
                messages.add(message);
              }
              await markConversationRead(conversationId);
            } else {
              unreadCounts[conversationId] = (unreadCounts[conversationId] ?? 0) + 1;
              showToast('Nouveau message reçu');
            }

            await refreshConversations();
            if (mounted) setState(() {});
          }

          if (data['type'] == 'conversation_created') {
            await refreshConversations();
          }

          if (data['type'] == 'new_status') {
            upsertStatus(data['payload']);
            showToast('Nouveau statut publié');
            if (mounted) setState(() {});
          }

          if (data['type'] == 'status_deleted') {
            final deletedId = data['payload']['id'];
            statuses.removeWhere((item) => item['id'] == deletedId);
            if (mounted) setState(() {});
          }

          if (data['type'] == 'message_deleted') {
            messages.removeWhere((item) => item['id'] == data['payload']['id']);
            await refreshConversations();
            if (mounted) setState(() {});
          }

          if (data['type'] == 'messages_read') {
            await refreshConversations();
          }
        },
        onDone: scheduleReconnect,
        onError: (_) => scheduleReconnect(),
      );
    } catch (_) {
      scheduleReconnect();
    }
  }

  void scheduleReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 3), connectWebSocket);
  }

  bool get wideScreen => MediaQuery.sizeOf(context).width >= 950;

  Map<String, dynamic>? get activeConversation {
    for (final conversation in conversations) {
      final item = Map<String, dynamic>.from(conversation);
      if (item['id'] == activeConversationId) return item;
    }
    return null;
  }

  List<Map<String, dynamic>> get visibleConversations {
    final result = <Map<String, dynamic>>[];
    final q = searchCtrl.text.trim().toLowerCase();

    for (final raw in conversations) {
      final c = Map<String, dynamic>.from(raw);

      if (section == AppSection.secure) {
        if (c['is_secure'] != true) continue;
      } else if (section == AppSection.groups) {
        if (c['type'] != 'group' || c['is_secure'] == true) continue;
      } else if (section == AppSection.chats) {
        if (c['is_secure'] == true) continue;
        if (groupsOnly && c['type'] != 'group') continue;
      }

      final title = '${c['display_title'] ?? c['title'] ?? ''}'.toLowerCase();
      final last = previewMessage(c['last_message']).toLowerCase();
      if (q.isNotEmpty && !title.contains(q) && !last.contains(q)) continue;

      result.add(c);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final conversationSection =
        section == AppSection.chats || section == AppSection.groups || section == AppSection.secure;

    if (wideScreen) {
      return Scaffold(
        body: appBackground(
          child: Row(
            children: [
              rail(),
              if (conversationSection) ...[
                SizedBox(width: 430, child: sidePanel()),
                VerticalDivider(width: 1, color: Colors.white.withOpacity(0.08)),
              ],
              Expanded(child: mainPanel()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: appBackground(
        child: activeConversationId != null && conversationSection ? mainPanel() : sidePanel(),
      ),
      bottomNavigationBar: mobileNavigation(),
    );
  }

  Widget appBackground({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.85, -0.95),
          radius: 1.35,
          colors: [
            Color(0xFF033A4C),
            Color(0xFF071B35),
            Color(0xFF150B33),
            Color(0xFF070817),
          ],
          stops: [0.0, 0.34, 0.72, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -160,
            child: decorativeOrb(const Color(0xFF00C8FF), 420, 0.18),
          ),
          Positioned(
            right: -190,
            bottom: -190,
            child: decorativeOrb(const Color(0xFF7C3AED), 460, 0.22),
          ),
          Positioned(
            top: 120,
            right: 180,
            child: decorativeOrb(const Color(0xFF2563EB), 220, 0.10),
          ),
          child,
        ],
      ),
    );
  }

  Widget decorativeOrb(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(opacity),
            blurRadius: 120,
            spreadRadius: 35,
          ),
        ],
      ),
    );
  }

  Widget glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.92),
            const Color(0xFFF8F7FF).withOpacity(0.86),
            const Color(0xFFEAF7FF).withOpacity(0.82),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.88), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C8FF).withOpacity(0.08),
            blurRadius: 36,
            offset: const Offset(-12, 16),
          ),
          BoxShadow(
            color: const Color(0xFF1E1B4B).withOpacity(0.13),
            blurRadius: 42,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget gradientTitleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061126), Color(0xFF042B44), Color(0xFF1238B5), Color(0xFF4C1D95)],
          stops: [0.0, 0.36, 0.70, 1.0],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.28),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -80, top: -95, child: decorativeOrb(const Color(0xFF00C8FF), 190, 0.16)),
          Positioned(right: 80, bottom: -115, child: decorativeOrb(const Color(0xFF7C3AED), 220, 0.17)),
          Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(colors: [Color(0xFF00C8FF), Color(0xFF2563EB), Color(0xFF7C3AED)]),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00C8FF).withOpacity(0.30), blurRadius: 28, offset: const Offset(0, 14)),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                    const SizedBox(height: 6),
                    Text(subtitle, style: const TextStyle(color: Color(0xFFD7E5F7), fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
        ],
      ),
    );
  }

  Widget mobileNavigation() {
    final sections = [
      AppSection.chats,
      AppSection.status,
      AppSection.groups,
      AppSection.secure,
      AppSection.settings,
    ];

    return NavigationBar(
      selectedIndex: sections.contains(section) ? sections.indexOf(section) : 0,
      onDestinationSelected: (index) {
        setState(() {
          section = sections[index];
          if (section != AppSection.chats && section != AppSection.groups && section != AppSection.secure) {
            activeConversationId = null;
          }
        });
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
        NavigationDestination(icon: Icon(Icons.circle_outlined), label: 'Statuts'),
        NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Groupes'),
        NavigationDestination(icon: Icon(Icons.lock_outline), label: 'Sécurisé'),
        NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), label: 'Compte'),
      ],
    );
  }

  Widget rail() {
    return Container(
      width: 88,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF061126), Color(0xFF0A1B35), Color(0xFF140B2E)],
        ),
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.10))),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 28, offset: const Offset(8, 0)),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          SololaLogo(logoUrl: widget.logoUrl, size: 58),
          const SizedBox(height: 20),
          for (final item in AppSection.values) navRailButton(item),
          IconButton(
            tooltip: 'Avis',
            color: Colors.white.withOpacity(0.82),
            onPressed: () => sendFeedback(),
            icon: const Icon(Icons.mail_outline),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Déconnexion',
            color: Colors.white.withOpacity(0.82),
            onPressed: () => widget.logout(),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget navRailButton(AppSection item) {
    final selected = section == item;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Tooltip(
        message: sectionLabel(item),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              section = item;
              if (item != AppSection.chats && item != AppSection.groups && item != AppSection.secure) {
                activeConversationId = null;
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 54,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: selected
                  ? const LinearGradient(colors: [Color(0xFF00C8FF), Color(0xFF2563EB), Color(0xFF7C3AED)])
                  : null,
              color: selected ? null : Colors.white.withOpacity(0.045),
              border: Border.all(color: selected ? Colors.white.withOpacity(0.20) : Colors.white.withOpacity(0.08)),
              boxShadow: selected
                  ? [BoxShadow(color: const Color(0xFF00C8FF).withOpacity(0.24), blurRadius: 24, offset: const Offset(0, 12))]
                  : [],
            ),
            child: Icon(sectionIcon(item), color: Colors.white, size: 25),
          ),
        ),
      ),
    );
  }

  String sectionLabel(AppSection value) {
    switch (value) {
      case AppSection.chats:
        return 'Discussions';
      case AppSection.status:
        return 'Statuts';
      case AppSection.groups:
        return 'Groupes';
      case AppSection.secure:
        return 'Sécurisé';
      case AppSection.settings:
        return 'Paramètres utilisateur';
      case AppSection.help:
        return 'Aide';
    }
  }

  IconData sectionIcon(AppSection value) {
    switch (value) {
      case AppSection.chats:
        return Icons.chat_bubble_outline;
      case AppSection.status:
        return Icons.circle_outlined;
      case AppSection.groups:
        return Icons.groups_outlined;
      case AppSection.secure:
        return Icons.lock_outline;
      case AppSection.settings:
        return Icons.manage_accounts_outlined;
      case AppSection.help:
        return Icons.help_outline;
    }
  }

  Widget sidePanel() {
    if (section == AppSection.status) return statusPage();
    if (section == AppSection.settings) return settingsPage();
    if (section == AppSection.help) return helpPage();

    final secureSection = section == AppSection.secure;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 18, 0, 18),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), bottomLeft: Radius.circular(30)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.86), Colors.white.withOpacity(0.66), const Color(0xFFEAF7FF).withOpacity(0.55)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.78)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF061126).withOpacity(0.18), blurRadius: 36, offset: const Offset(0, 20)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sideHeader(sectionLabel(section)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: secureSection ? () => createSecurePrivate() : () => createPrivate(),
                  icon: Icon(secureSection ? Icons.lock_person : Icons.person_add),
                  label: Text(secureSection ? 'Sécurisée' : 'Conversation'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: secureSection ? () => createSecureGroup() : () => createGroup(),
                  icon: Icon(secureSection ? Icons.lock : Icons.group_add),
                  label: Text(secureSection ? 'Groupe sécurisé' : 'Groupe'),
                ),
              ),
            ],
          ),
          if (section == AppSection.chats) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFF061126).withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.65)),
              ),
              child: Row(
                children: [
                  Expanded(child: segmentButton('Toutes', !groupsOnly, () => setState(() => groupsOnly = false))),
                  Expanded(child: segmentButton('Groupes', groupsOnly, () => setState(() => groupsOnly = true))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Expanded(
            child: visibleConversations.isEmpty
                ? Center(
                    child: glassCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.chat_bubble_outline, size: 54, color: Color(0xFF4F46E5)),
                        SizedBox(height: 12),
                        Text('Aucune conversation ici.', style: TextStyle(fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text('Crée une discussion ou un groupe.', textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                : ListView.separated(
                    itemCount: visibleConversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => conversationTile(visibleConversations[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget segmentButton(String text, bool selected, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : const Color(0xFF334155),
        backgroundColor: selected ? const Color(0xFF2563EB) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget sideHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(colors: [Color(0xFF00C8FF), Color(0xFF7C3AED)]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.9, color: Color(0xFF0F172A)))),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Color(0xFF2563EB)),
            hintText: 'Rechercher',
            filled: true,
            fillColor: Colors.white.withOpacity(0.92),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: Colors.white.withOpacity(0.90))),
            focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(22)), borderSide: BorderSide(color: Color(0xFF00C8FF), width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget conversationTile(Map<String, dynamic> conversation) {
    final last = conversation['last_message'];
    final count = unreadCounts[conversation['id']] ?? 0;

    return ListTile(
      selected: conversation['id'] == activeConversationId,
      leading: conversationAvatar(conversation),
      title: Text(
        '${conversation['display_title'] ?? 'Conversation'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        previewMessage(last),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(formatHour(last?['created_at'])),
          if (count > 0)
            CircleAvatar(
              radius: 11,
              child: Text('$count', style: const TextStyle(fontSize: 10)),
            ),
        ],
      ),
      onTap: () async {
        activeConversationId = conversation['id'];
        await loadMessages(conversation['id']);
      },
    );
  }

  Widget conversationAvatar(Map<String, dynamic> conversation, {double radius = 24}) {
    if (conversation['is_secure'] == true) {
      return CircleAvatar(radius: radius, child: const Icon(Icons.lock_outline));
    }

    if (conversation['type'] == 'group') {
      return CircleAvatar(radius: radius, child: const Icon(Icons.groups_outlined));
    }

    final members = (conversation['members'] as List?) ?? [];
    Map<String, dynamic>? other;

    for (final member in members) {
      if (member is Map && member['id'] != widget.user['id']) {
        other = Map<String, dynamic>.from(member);
        break;
      }
    }

    final avatarUrl = other?['avatar_url'];
    if (avatarUrl != null && '$avatarUrl'.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(widget.api.fileUrl(avatarUrl)),
      );
    }

    return CircleAvatar(
      radius: radius,
      child: Text(initials(conversation['display_title'])),
    );
  }

  Widget mainPanel() {
    if (section == AppSection.status) return statusPage();
    if (section == AppSection.settings) return settingsPage();
    if (section == AppSection.help) return helpPage();

    final conversation = activeConversation;
    if (conversation == null) {
      return Center(
        child: Container(
          width: 560,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(46, 44, 46, 40),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF061126), Color(0xFF092443), Color(0xFF1E1B4B), Color(0xFF3B1B7A)],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF00C8FF).withOpacity(0.18), blurRadius: 44, offset: const Offset(0, 20)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SololaLogo(logoUrl: widget.logoUrl, size: 110, showText: true),
              const SizedBox(height: 20),
              const Text(
                'Sélectionne une discussion pour commencer.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Messages, statuts, fichiers et conversations chiffrées sont regroupés dans un espace propre.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFCFE3FF), height: 1.35),
              ),
            ],
          ),
        ),
      );
    }

    return chatPanel(conversation);
  }

  Widget chatPanel(Map<String, dynamic> conversation) {
    final locked = conversation['is_secure'] == true && !securePins.containsKey(conversation['id']);
    final temporary = temporarySecurity.containsKey(conversation['id']);

    final filteredMessages = searchCtrl.text.trim().isEmpty
        ? messages
        : messages.where((message) {
            final raw = jsonEncode(message).toLowerCase();
            final clear = decryptedMessages[message['id']]?.toLowerCase() ?? '';
            return raw.contains(searchCtrl.text.toLowerCase()) || clear.contains(searchCtrl.text.toLowerCase());
          }).toList();

    return Column(
      children: [
        chatHeader(conversation, locked, temporary),
        if (locked)
          Expanded(child: lockedConversationPanel(conversation))
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: TextField(
              controller: searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Rechercher dans la conversation',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: filteredMessages.length,
              itemBuilder: (context, index) {
                return messageBubble(Map<String, dynamic>.from(filteredMessages[index]));
              },
            ),
          ),
          composer(conversation),
        ],
      ],
    );
  }

  Widget chatHeader(Map<String, dynamic> conversation, bool locked, bool temporary) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (!wideScreen)
            IconButton(
              onPressed: () => setState(() => activeConversationId = null),
              icon: const Icon(Icons.arrow_back),
            ),
          conversationAvatar(conversation, radius: 25),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${conversation['display_title'] ?? 'Conversation'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  conversation['is_secure'] == true
                      ? 'Conversation 100 % chiffrée'
                      : temporary
                          ? 'Chiffrement temporaire activé'
                          : 'Temps réel',
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () {
              if (conversation['is_secure'] == true) {
                togglePermanentSecure(conversation);
              } else {
                toggleTemporarySecure(conversation);
              }
            },
            icon: Icon(
              conversation['is_secure'] == true
                  ? locked
                      ? Icons.lock_open
                      : Icons.lock
                  : temporary
                      ? Icons.lock_open
                      : Icons.lock_outline,
            ),
            label: Text(
              conversation['is_secure'] == true
                  ? locked
                      ? 'Déverrouiller'
                      : 'Verrouiller'
                  : temporary
                      ? 'Temporaire ON'
                      : 'Temporaire',
            ),
          ),
          const SizedBox(width: 8),
          if (conversation['type'] == 'private')
            IconButton(
              tooltip: 'Appel',
              onPressed: () => showToast('Module appel prêt. WebRTC complet à finaliser.'),
              icon: const Icon(Icons.call_outlined),
            ),
        ],
      ),
    );
  }

  Widget lockedConversationPanel(Map<String, dynamic> conversation) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 12),
              const Text('Conversation sécurisée', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('Indice : ${conversation['security_hint'] ?? 'Aucun'}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => togglePermanentSecure(conversation),
                child: const Text('Entrer le PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget composer(Map<String, dynamic> conversation) {
    final secure = conversation['is_secure'] == true || temporarySecurity.containsKey(conversation['id']);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Envoyer fichier',
            onPressed: () => uploadFile(conversation, encrypted: false),
            icon: const Icon(Icons.attach_file),
          ),
          IconButton(
            tooltip: 'Envoyer fichier chiffré',
            onPressed: () => uploadFile(conversation, encrypted: true),
            icon: const Icon(Icons.enhanced_encryption_outlined),
          ),
          Expanded(
            child: TextField(
              controller: messageCtrl,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: secure ? 'Message automatiquement chiffré...' : 'Écrire un message...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onSubmitted: (_) => sendMessage(conversation),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () => sendMessage(conversation),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  Widget messageBubble(Map<String, dynamic> message) {
    final mine = message['sender_id'] == widget.user['id'];
    final type = '${message['message_type']}';

    Widget content;

    if (type == 'encrypted_text') {
      content = encryptedMessageWidget(message);
    } else if (message['file'] != null) {
      final file = message['file'];
      content = InkWell(
        onTap: () => launchUrl(Uri.parse(widget.api.fileUrl(file['download_url']))),
        child: Text(
          '📎 ${file['original_filename']}',
          style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
        ),
      );
    } else {
      content = Text('${message['content'] ?? ''}');
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Card(
          color: mine ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine)
                  Text(
                    '${message['sender_pseudo'] ?? ''}',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                  ),
                content,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatHour(message['created_at']), style: const TextStyle(fontSize: 11)),
                    if (mine)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(messageStatusLabel(message['status']), style: const TextStyle(fontSize: 11)),
                      ),
                    IconButton(
                      iconSize: 18,
                      onPressed: () => forwardMessage(message),
                      icon: const Icon(Icons.forward),
                    ),
                    if (mine)
                      IconButton(
                        iconSize: 18,
                        onPressed: () => deleteMessage(message),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget encryptedMessageWidget(Map<String, dynamic> message) {
    final id = message['id'] as int;

    if (decryptedMessages[id] != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔓 Message déchiffré', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(decryptedMessages[id]!),
        ],
      );
    }

    Map<String, dynamic> payload = {};
    try {
      payload = Map<String, dynamic>.from(jsonDecode('${message['content']}'));
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🔐 Message chiffré', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Indice : ${payload['hint'] ?? 'Aucun'}'),
        SelectableText(
          '${payload['ciphertext'] ?? message['content']}',
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () => decryptMessage(message),
          child: const Text('Déchiffrer avec PIN'),
        ),
      ],
    );
  }

  String messageStatusLabel(dynamic status) {
    if (status == 'read') return '✓✓ lu';
    if (status == 'delivered') return '✓✓ reçu';
    return '✓ envoyé';
  }

  Map<String, String>? securityContextFor(Map<String, dynamic> conversation) {
    final id = conversation['id'] as int;

    if (conversation['is_secure'] == true) {
      final pin = securePins[id];
      if (pin == null) {
        showToast('Déverrouille d’abord cette conversation.');
        return null;
      }

      return {
        'pin': pin,
        'hint': '${conversation['security_hint'] ?? ''}',
        'mode': 'permanent_secure',
      };
    }

    if (temporarySecurity.containsKey(id)) {
      return temporarySecurity[id];
    }

    return null;
  }

  Future<void> sendMessage(Map<String, dynamic> conversation) async {
    final text = messageCtrl.text.trim();
    if (text.isEmpty) return;

    messageCtrl.clear();

    try {
      final security = securityContextFor(conversation);

      if (security != null) {
        final encrypted = await PinCrypto.encryptText(
          clearText: text,
          pin: security['pin']!,
          hint: security['hint'] ?? '',
          mode: security['mode'] ?? 'temporary_secure',
        );

        await widget.api.post('/conversations/${conversation['id']}/messages', {
          'content': jsonEncode(encrypted),
          'message_type': 'encrypted_text',
        });
      } else {
        await widget.api.post('/conversations/${conversation['id']}/messages', {
          'content': text,
          'message_type': 'text',
        });
      }
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> decryptMessage(Map<String, dynamic> message, {String? suppliedPin}) async {
    final pin = suppliedPin ??
        await textDialog(
          context,
          title: 'Déchiffrement',
          label: 'PIN',
          obscure: true,
        );

    if (pin == null || pin.isEmpty) return;

    try {
      final payload = Map<String, dynamic>.from(jsonDecode('${message['content']}'));
      decryptedMessages[message['id']] = await PinCrypto.decryptText(payload: payload, pin: pin);
      if (mounted) setState(() {});
    } catch (_) {
      showToast('PIN incorrect ou message impossible à déchiffrer.');
    }
  }

  Future<void> togglePermanentSecure(Map<String, dynamic> conversation) async {
    final id = conversation['id'] as int;

    if (securePins.containsKey(id)) {
      securePins.remove(id);
      decryptedMessages.clear();
      setState(() {});
      return;
    }

    final pin = await textDialog(
      context,
      title: 'Déverrouiller',
      label: 'PIN - indice : ${conversation['security_hint'] ?? 'Aucun'}',
      obscure: true,
    );

    if (pin == null || pin.isEmpty) return;

    securePins[id] = pin;

    for (final rawMessage in messages) {
      final message = Map<String, dynamic>.from(rawMessage);
      if (message['message_type'] == 'encrypted_text') {
        await decryptMessage(message, suppliedPin: pin);
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> toggleTemporarySecure(Map<String, dynamic> conversation) async {
    final id = conversation['id'] as int;

    if (temporarySecurity.containsKey(id)) {
      temporarySecurity.remove(id);
      setState(() {});
      return;
    }

    final result = await temporarySecureDialog(context);
    if (result == null) return;

    temporarySecurity[id] = result;
    setState(() {});
  }

  Future<void> uploadFile(Map<String, dynamic> conversation, {required bool encrypted}) async {
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null) return;

      final file = picked.files.single;

      if (file.size > 10 * 1024 * 1024) {
        showToast('Fichier trop lourd : limite 10 Mo.');
        return;
      }

      if (!encrypted) {
        await widget.api.upload('/conversations/${conversation['id']}/upload', file);
        return;
      }

      final pin = await textDialog(
        context,
        title: 'Fichier chiffré',
        label: 'PIN',
        obscure: true,
      );

      if (pin == null || pin.isEmpty) return;

      final bytes = file.bytes;
      if (bytes == null) {
        showToast('Lecture du fichier impossible.');
        return;
      }

      final encryptedPayload = await PinCrypto.encryptText(
        clearText: base64Encode(bytes),
        pin: pin,
        hint: 'fichier chiffré',
        mode: 'encrypted_file',
      );

      final encoded = Uint8List.fromList(utf8.encode(jsonEncode(encryptedPayload)));

      final encryptedFile = PlatformFile(
        name: '${file.name}.encrypted',
        size: encoded.length,
        bytes: encoded,
      );

      await widget.api.upload('/conversations/${conversation['id']}/upload', encryptedFile);
      showToast('Fichier chiffré envoyé. Tracking garde le hash du fichier chiffré.');
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> createPrivate() async {
    final phone = await textDialog(context, title: 'Nouvelle conversation', label: 'Numéro');
    if (phone == null || phone.isEmpty) return;

    try {
      final conversation = await widget.api.post('/conversations/private', {'phone_number': phone});
      await refreshConversations();
      activeConversationId = conversation['id'];
      section = AppSection.chats;
      await loadMessages(conversation['id']);
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> createSecurePrivate() async {
    final result = await secureConversationDialog(context);
    if (result == null) return;

    try {
      final conversation = await widget.api.post('/conversations/private', {
        'phone_number': result['phone'],
        'is_secure': true,
        'security_hint': result['hint'],
      });

      securePins[conversation['id']] = result['pin']!;
      await refreshConversations();
      activeConversationId = conversation['id'];
      section = AppSection.secure;
      await loadMessages(conversation['id']);
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> createGroup() async {
    final result = await groupDialog(context, secure: false);
    if (result == null) return;

    try {
      final conversation = await widget.api.post('/conversations/group', result);
      await refreshConversations();
      activeConversationId = conversation['id'];
      section = AppSection.groups;
      await loadMessages(conversation['id']);
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> createSecureGroup() async {
    final result = await groupDialog(context, secure: true);
    if (result == null) return;

    final pin = result.remove('pin');

    try {
      final conversation = await widget.api.post('/conversations/group', result);
      securePins[conversation['id']] = '$pin';
      await refreshConversations();
      activeConversationId = conversation['id'];
      section = AppSection.secure;
      await loadMessages(conversation['id']);
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> forwardMessage(Map<String, dynamic> message) async {
    final list = conversations.map((conversation) {
      return '${conversation['id']} - ${conversation['display_title']}';
    }).join('\n');

    final id = await textDialog(context, title: 'Transfert', label: 'ID conversation cible\n$list');
    if (id == null || id.isEmpty) return;

    try {
      await widget.api.post('/messages/${message['id']}/forward', {
        'conversation_id': int.parse(id),
      });
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> deleteMessage(Map<String, dynamic> message) async {
    try {
      await widget.api.delete('/messages/${message['id']}');
      messages.removeWhere((item) => item['id'] == message['id']);
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  Widget statusPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 32),
      children: [
        gradientTitleCard(
          title: 'Statuts',
          subtitle: 'Partage une photo. Appuie sur une carte pour l’afficher en plein écran.',
          icon: Icons.photo_library_outlined,
          action: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.18),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: () => publishStatus(),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Poster'),
          ),
        ),
        const SizedBox(height: 26),
        if (statuses.isEmpty)
          Center(
            child: glassCard(
              padding: const EdgeInsets.all(34),
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.photo_outlined, size: 62, color: Color(0xFF2563EB)),
                SizedBox(height: 14),
                Text('Aucun statut publié.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                SizedBox(height: 6),
                Text('Ajoute une photo pour tester les statuts en temps réel.'),
              ]),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: statuses.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 285,
              crossAxisSpacing: 22,
              mainAxisSpacing: 22,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              final status = Map<String, dynamic>.from(statuses[index]);
              final file = status['file'];
              final mine = isMyStatus(status);

              return InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => showStatusViewer(index),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white.withOpacity(0.94), const Color(0xFFEAF7FF).withOpacity(0.84)],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.95)),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF061126).withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 18)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    widget.api.fileUrl(file['download_url']),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, __, ___) => Container(
                                      alignment: Alignment.center,
                                      color: const Color(0xFFEFF4FF),
                                      child: const Icon(Icons.broken_image_outlined, size: 48),
                                    ),
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.black.withOpacity(0.18), Colors.transparent, Colors.black.withOpacity(0.18)],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  CircleAvatar(radius: 18, backgroundColor: const Color(0xFFE0EAFF), child: Text(initials(status['user']?['pseudo']))),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${status['user']?['pseudo'] ?? 'Utilisateur'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                        ),
                                        Text(formatHour(status['created_at']), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (mine)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.black.withOpacity(0.46),
                            borderRadius: BorderRadius.circular(18),
                            child: IconButton(
                              tooltip: 'Supprimer ce statut',
                              color: Colors.white,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => deleteStatus(status),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  bool isMyStatus(Map<String, dynamic> status) {
    final owner = status['user'];
    if (owner is Map) return owner['id'] == widget.user['id'];
    return false;
  }

  Future<void> deleteStatus(Map<String, dynamic> status) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer le statut ?'),
        content: const Text('Cette photo de statut sera retirée pour tous les utilisateurs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.api.delete('/statuses/${status['id']}');
      statuses.removeWhere((item) => item['id'] == status['id']);
      if (mounted) setState(() {});
      showToast('Statut supprimé.');
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> publishStatus() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null) return;

      final caption = await textDialog(
            context,
            title: 'Statut',
            label: 'Légende',
            requiredValue: false,
          ) ??
          '';

      final status = await widget.api.upload(
        '/statuses',
        picked.files.single,
        fields: {'caption': caption},
      );

      upsertStatus(status);
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  void showStatusViewer(int startIndex) {
    int index = startIndex;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final status = Map<String, dynamic>.from(statuses[index]);
          final file = status['file'];
          final mine = isMyStatus(status);

          return Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.network(
                    widget.api.fileUrl(file['download_url']),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 70),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                        ),
                      ),
                      child: ListTile(
                        textColor: Colors.white,
                        iconColor: Colors.white,
                        leading: CircleAvatar(child: Text(initials(status['user']?['pseudo']))),
                        title: Text('${status['user']?['pseudo'] ?? 'Utilisateur'}'),
                        subtitle: Text(formatHour(status['created_at'])),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mine)
                              IconButton(
                                tooltip: 'Supprimer',
                                onPressed: () async {
                                  Navigator.pop(dialogContext);
                                  await deleteStatus(status);
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          color: Colors.white,
                          onPressed: index > 0 ? () => setDialogState(() => index--) : null,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            '${status['caption'] ?? ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton.filledTonal(
                          color: Colors.white,
                          onPressed: index < statuses.length - 1 ? () => setDialogState(() => index++) : null,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget settingsPage() {
    final colors = <Color>[
      const Color(0xFF2563EB),
      const Color(0xFF10B981),
      const Color(0xFF7C3AED),
      const Color(0xFFF97316),
      const Color(0xFFE11D48),
    ];

    final privacy = Map<String, dynamic>.from(widget.user['privacy'] ?? <String, dynamic>{
      'show_online': true,
      'allow_calls': true,
      'allow_group_invites': true,
      'show_avatar': true,
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        gradientTitleCard(
          title: 'Paramètres utilisateur',
          subtitle: 'Profil, préférences, confidentialité et notifications. Les paramètres système sont réservés à /admin.',
          icon: Icons.manage_accounts_outlined,
          action: OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/admin/login'),
            icon: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
            label: const Text('Administration', style: TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 860;
            final profile = glassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Profil utilisateur', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  Center(child: profileAvatar(radius: constraints.maxWidth < 520 ? 58 : 74)),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => updateAvatar(),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Modifier la photo'),
                    ),
                  ),
                  const Divider(height: 30),
                  profileLine('Nom', '${widget.user['pseudo'] ?? ''}'),
                  profileLine('Téléphone', '${widget.user['phone_number'] ?? ''}'),
                  profileLine('Email', '${widget.user['email'] ?? 'Non défini'}'),
                  profileLine('À propos', '${widget.user['info'] ?? 'Disponible'}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => editProfile(),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Modifier profil'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => editEmail(),
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('Modifier email'),
                      ),
                    ],
                  ),
                ],
              ),
            );

            final display = glassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Préférences d’affichage', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in colors)
                        InkWell(
                          onTap: () => widget.onColorChanged(color),
                          borderRadius: BorderRadius.circular(50),
                          child: CircleAvatar(backgroundColor: color, radius: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widget.darkMode,
                    onChanged: (value) => widget.onDarkModeChanged(value),
                    title: const Text('Mode sombre', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: compactMode,
                    onChanged: (value) => saveNotificationPreference('solola_compact_mode', value),
                    title: const Text('Affichage compact', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );

            if (!twoColumns) {
              return Column(children: [
                profile,
                const SizedBox(height: 16),
                display,
              ]);
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: profile),
                const SizedBox(width: 16),
                Expanded(child: display),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 860;
            final privacyCard = glassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Confidentialité', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  privacySwitch('Afficher mon statut en ligne', privacy, 'show_online'),
                  privacySwitch('Autoriser les appels', privacy, 'allow_calls'),
                  privacySwitch('Autoriser les invitations de groupe', privacy, 'allow_group_invites'),
                  privacySwitch('Afficher ma photo de profil', privacy, 'show_avatar'),
                ],
              ),
            );

            final notificationsCard = glassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notifications', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: notifyMessages,
                    onChanged: (value) => saveNotificationPreference('solola_notify_messages', value),
                    title: const Text('Messages privés', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Préférence locale côté appareil.'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: notifyGroups,
                    onChanged: (value) => saveNotificationPreference('solola_notify_groups', value),
                    title: const Text('Groupes', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Préférence locale côté appareil.'),
                  ),
                ],
              ),
            );

            if (!twoColumns) {
              return Column(children: [
                privacyCard,
                const SizedBox(height: 16),
                notificationsCard,
              ]);
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: privacyCard),
                const SizedBox(width: 16),
                Expanded(child: notificationsCard),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        glassCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Session', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              const Text(
                'L’URL API, le logo global et les paramètres techniques ne sont plus modifiables dans le compte utilisateur.',
                style: TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => sendFeedback(),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Envoyer un avis'),
                  ),
                  FilledButton.icon(
                    onPressed: () => widget.logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Déconnexion'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget profileLine(String title, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: false,
      title: Text(title, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
      subtitle: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
    );
  }

  Widget profileAvatar({double radius = 48}) {
    final avatarUrl = widget.user['avatar_url'];
    if (avatarUrl != null && '$avatarUrl'.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(widget.api.fileUrl(avatarUrl)),
      );
    }

    return CircleAvatar(
      radius: radius,
      child: Text(initials(widget.user['pseudo']), style: TextStyle(fontSize: radius / 1.6)),
    );
  }

  Widget privacySwitch(String title, Map<String, dynamic> privacy, String key) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: privacy[key] == true,
      onChanged: (value) => savePrivacy(key, value),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> updateAvatar() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null) return;

      final updated = await widget.api.upload('/auth/me/avatar', picked.files.single);
      await widget.updateUser(Map<String, dynamic>.from(updated));
      await refreshConversations();
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> editProfile() async {
    final pseudo = await textDialog(context, title: 'Profil', label: 'Nouveau pseudo');
    if (pseudo == null || pseudo.isEmpty) return;

    try {
      final updated = await widget.api.patch('/auth/me/profile', {
        'pseudo': pseudo,
        'info': widget.user['info'] ?? '',
        'email': widget.user['email'] ?? '',
      });

      await widget.updateUser(Map<String, dynamic>.from(updated));
      await refreshConversations();
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> editEmail() async {
    final email = await textDialog(context, title: 'Email de connexion', label: 'Nouvel email');
    if (email == null || email.trim().isEmpty) return;

    try {
      final updated = await widget.api.patch('/auth/me/profile', {
        'pseudo': widget.user['pseudo'] ?? '',
        'info': widget.user['info'] ?? '',
        'email': email.trim(),
      });

      await widget.updateUser(Map<String, dynamic>.from(updated));
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  Future<void> savePrivacy(String key, bool value) async {
    final privacy = Map<String, dynamic>.from(widget.user['privacy'] ?? {});
    privacy[key] = value;

    try {
      final updated = await widget.api.patch('/auth/me/privacy', {
        'show_online': privacy['show_online'] ?? true,
        'allow_calls': privacy['allow_calls'] ?? true,
        'allow_group_invites': privacy['allow_group_invites'] ?? true,
        'show_avatar': privacy['show_avatar'] ?? true,
      });

      await widget.updateUser(Map<String, dynamic>.from(updated));
      await refreshConversations();
      if (mounted) setState(() {});
    } catch (e) {
      showToast(e);
    }
  }

  Widget helpPage() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: const [
        Text('Aide / À propos', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        SizedBox(height: 14),
        Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Solola Flutter est un prototype de messagerie sécurisée. '
              'Le PIN reste côté application et n’est jamais envoyé au serveur.',
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Solola Tracking est maintenant une application administrateur séparée de Solola. '
              'Il conserve les preuves : utilisateurs, heures, fichiers, statuts, SHA-256 et audit.',
            ),
          ),
        ),
      ],
    );
  }

  void sendFeedback() {
    launchUrl(
      Uri.parse('mailto:kalodave708@gmail.com?subject=Avis%20Solola&body=Bonjour,%20voici%20mon%20avis%20sur%20Solola%20:%20'),
    );
  }

  void showToast(Object error) {
    if (!mounted) return;
    final message = '$error'.replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
