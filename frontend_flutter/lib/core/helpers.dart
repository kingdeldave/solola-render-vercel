part of solola_app;

String initials(dynamic value) {
  final text = '${value ?? '?'}'.trim();
  if (text.isEmpty) return '?';
  return text.substring(0, text.length < 2 ? text.length : 2).toUpperCase();
}

String previewMessage(dynamic message) {
  if (message == null) return 'Aucun message';
  if (message['message_type'] == 'encrypted_text') return '🔐 Message chiffré';
  if (message['file'] != null) return '📎 ${message['file']['original_filename']}';
  return '${message['content'] ?? ''}';
}

String formatHour(dynamic isoValue) {
  try {
    if (isoValue == null) return '';
    return DateTime.parse('$isoValue').toLocal().toString().substring(11, 16);
  } catch (_) {
    return '';
  }
}
