import 'package:flutter_test/flutter_test.dart';
import 'package:cystem/models/chat_models.dart';

void main() {
  test('message JSON round trip preserves attachment/source metadata', () {
    final original = ChatMessage(
      id: 'm',
      chatId: 'c',
      role: MessageRole.assistant,
      content: 'hello',
      createdAt: DateTime.utc(2026, 1, 1),
      attachments: [
        ChatAttachment(
          id: 'a',
          path: '/tmp/a.png',
          name: 'a.png',
          mimeType: 'image/png',
          size: 10,
        ),
      ],
      sources: [
        const SourceRecord(title: 'Example', url: 'https://example.com'),
      ],
    );
    final copy = ChatMessage.fromJson(original.toJson());
    expect(copy.content, 'hello');
    expect(copy.attachments.single.name, 'a.png');
    expect(copy.sources.single.url, 'https://example.com');
  });
}
