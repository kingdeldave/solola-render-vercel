part of solola_app;

class ApiClient {
  String baseUrl;
  String? token;

  ApiClient({required this.baseUrl, required this.token});

  Uri uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> headers({bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String websocketUrl() {
    return '${baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://')}/ws?token=${Uri.encodeComponent(token ?? '')}';
  }

  String fileUrl(dynamic path) {
    final value = '${path ?? ''}';
    if (value.isEmpty) return '';

    final absolute = value.startsWith('http') ? value : '$baseUrl$value';

    // Pour les téléchargements privés ouverts par le navigateur, on ajoute le token
    // comme paramètre court. Le backend vérifie aussi l'autorisation côté serveur.
    if (token == null || token!.isEmpty || !absolute.contains('/files/')) {
      return absolute;
    }

    final separator = absolute.contains('?') ? '&' : '?';
    return '$absolute${separator}access_token=${Uri.encodeComponent(token!)}';
  }

  Future<dynamic> get(String path) async {
    return decode(await http.get(uri(path), headers: headers(json: false)));
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    return decode(await http.post(uri(path), headers: headers(), body: jsonEncode(body)));
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    return decode(await http.patch(uri(path), headers: headers(), body: jsonEncode(body)));
  }

  Future<dynamic> delete(String path) async {
    return decode(await http.delete(uri(path), headers: headers(json: false)));
  }

  Future<dynamic> upload(String path, PlatformFile file, {Map<String, String>? fields}) async {
    final request = http.MultipartRequest('POST', uri(path));

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields.addAll(fields ?? {});

    if (file.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes('upload', file.bytes!, filename: file.name));
    } else if (file.path != null) {
      request.files.add(await http.MultipartFile.fromPath('upload', file.path!, filename: file.name));
    } else {
      throw Exception('Fichier invalide.');
    }

    return decode(await http.Response.fromStream(await request.send()));
  }

  dynamic decode(http.Response response) {
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      data = response.body;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? data['detail'] : data;
      throw Exception(friendlyError('$detail', response.statusCode));
    }

    return data;
  }

  String friendlyError(String message, int statusCode) {
    if (statusCode == 401) return 'Session expirée ou accès refusé.';
    if (statusCode == 403) return 'Action refusée : droits insuffisants.';
    if (statusCode == 404) return 'Élément introuvable.';
    if (statusCode == 413) return 'Fichier trop lourd.';
    if (message.contains('XMLHttpRequest') ||
        message.contains('Connection') ||
        message.contains('Failed host lookup') ||
        message.contains('SocketException')) {
      return "Impossible de joindre le backend. Vérifie l'URL de l'API Render et la configuration CORS.";
    }
    return message.isEmpty ? 'Erreur HTTP $statusCode' : message;
  }
}

/// Chiffrement local avec PIN : AES-GCM + PBKDF2.
/// Le PIN n'est jamais envoyé au backend.
