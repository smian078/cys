import 'package:flutter_test/flutter_test.dart';
import 'package:cystem/core/services/backup_codec.dart';

void main() {
  test('backup codec round trips structured storage data', () {
    const codec = BackupCodec();
    final raw = codec.encode(
      chats: [
        {'id': 'c1', 'title': 'Test', 'pinned': 1},
      ],
      messages: [
        {'id': 'm1', 'chat_id': 'c1', 'content': 'hello'},
      ],
      memories: [
        {'id': 'r1', 'key': 'style', 'value': 'concise'},
      ],
      attachments: [
        {'id': 'a1', 'name': 'image.png', 'mime': 'image/png'},
      ],
      exportedAt: DateTime.utc(2026, 1, 1),
    );

    final decoded = codec.decode(raw);
    expect(decoded['version'], 1);
    expect((decoded['chats'] as List).single['title'], 'Test');
    expect((decoded['attachments'] as List).single['mime'], 'image/png');
  });

  test('rejects malformed backups', () {
    const codec = BackupCodec();
    expect(() => codec.decode('{"version":2}'), throwsFormatException);
  });
}
