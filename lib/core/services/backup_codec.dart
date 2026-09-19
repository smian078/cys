import 'dart:convert';

class BackupCodec {
  const BackupCodec();

  String encode({
    required List<Map<String, Object?>> chats,
    required List<Map<String, Object?>> messages,
    required List<Map<String, Object?>> memories,
    required List<Map<String, Object?>> attachments,
    DateTime? exportedAt,
  }) {
    return jsonEncode({
      'version': 1,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'chats': chats,
      'messages': messages,
      'memories': memories,
      'attachments': attachments,
    });
  }

  Map<String, dynamic> decode(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>)
      throw const FormatException('Backup root must be a JSON object.');
    if (data['version'] != 1)
      throw const FormatException('Unsupported backup version.');
    for (final key in const ['chats', 'messages', 'memories', 'attachments']) {
      if (data[key] is! List)
        throw FormatException('Backup field "$key" must be an array.');
    }
    return data;
  }
}
