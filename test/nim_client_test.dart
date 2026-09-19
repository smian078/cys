import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:cystem/models/stream_events.dart';
import 'package:cystem/services/nim_client.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.payload);
  final String payload;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(payload)]),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  test('parses streamed text, reasoning and tool-call chunks', () async {
    final payload = [
      'data: {"id":"r1","model":"nvidia/test","choices":[{"delta":{"reasoning_content":"think ","content":"Hello"}}]}\n\n',
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"open_phone_app","arguments":"{\\"package\\":\\"settings\\"}"}}]}}]}\n\n',
      'data: {"choices":[{"finish_reason":"stop","delta":{}}],"usage":{"total_tokens":12}}\n\n',
      'data: [DONE]\n\n',
    ].join();

    final events = await NimClient(client: _FakeClient(payload))
        .stream(
          baseUrl: 'https://example.com/v1',
          apiKey: 'key',
          model: 'nvidia/test',
          messages: const [],
        )
        .toList();

    expect(events.whereType<TextDelta>().single.text, 'Hello');
    expect(events.whereType<ReasoningDelta>().single.text, 'think ');
    final tool = events.whereType<ToolCallDelta>().single;
    expect(tool.id, 'call_1');
    expect(tool.name, 'open_phone_app');
    expect(events.whereType<StreamFinished>(), isNotEmpty);
  });
}
