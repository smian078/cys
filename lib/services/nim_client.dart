import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/utils/retry.dart';
import '../models/stream_events.dart';

class NimClient {
  NimClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Stream<CystemStreamEvent> stream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    double temperature = 1.0,
    double topP = 0.95,
    int? seed,
    String reasoningEffort = 'low',
  }) async* {
    final normalizedEffort = reasoningEffort.toLowerCase();
    final chatTemplate = <String, dynamic>{
      'enable_thinking': normalizedEffort != 'none',
      if (normalizedEffort == 'low') 'low_effort': true,
    };
    final payload = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': true,
      'temperature': temperature,
      'top_p': topP,
      if (seed != null) 'seed': seed,
      'chat_template_kwargs': chatTemplate,
      'max_tokens': 8192,
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
    });

    late http.StreamedResponse response;
    try {
      response = await withRetry(
        action: () async {
          final request = http.Request(
            'POST',
            Uri.parse('$baseUrl/chat/completions'),
          );
          request.headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          });
          request.body = payload;
          final result = await _client.send(request);
          if (result.statusCode == 429 || result.statusCode >= 500) {
            final body = await result.stream.bytesToString();
            throw http.ClientException(
              'Retryable NVIDIA HTTP ${result.statusCode}: $body',
              request.url,
            );
          }
          return result;
        },
        shouldRetry: (error) => error is http.ClientException,
      );
    } catch (e) {
      yield StreamError(e.toString());
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      yield StreamError('NVIDIA HTTP ${response.statusCode}: $body');
      return;
    }

    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      final parts = buffer.split(RegExp(r'\n\n|\r\n\r\n'));
      buffer = parts.removeLast();
      for (final raw in parts) {
        final dataLines = raw
            .split('\n')
            .where((line) => line.startsWith('data:'))
            .map((line) => line.substring(5).trim())
            .toList();
        if (dataLines.isEmpty) continue;
        final data = dataLines.join('\n');
        if (data == '[DONE]') {
          yield const StreamFinished(reason: 'stop');
          continue;
        }
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choice = ((json['choices'] as List?)?.firstOrNull as Map?)
              ?.cast<String, dynamic>();
          final delta = (choice?['delta'] as Map?)?.cast<String, dynamic>();
          if (delta != null) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty)
              yield TextDelta(content);
            final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
            if (reasoning is String && reasoning.isNotEmpty)
              yield ReasoningDelta(reasoning);
            final tc = delta['tool_calls'];
            if (tc is List) {
              for (var i = 0; i < tc.length; i++) {
                final item = (tc[i] as Map).cast<String, dynamic>();
                final fn = (item['function'] as Map?)?.cast<String, dynamic>();
                yield ToolCallDelta(
                  index: (item['index'] as num?)?.toInt() ?? i,
                  id: item['id'] as String?,
                  name: fn?['name'] as String?,
                  arguments: fn?['arguments'] as String?,
                );
              }
            }
          }
          final usage = (json['usage'] as Map?)?.cast<String, dynamic>();
          if (choice != null &&
              (choice['finish_reason'] != null || usage != null)) {
            yield StreamFinished(
              reason: choice['finish_reason'] as String?,
              responseId: json['id'] as String?,
              model: json['model'] as String?,
              usage: usage,
            );
          }
        } catch (e) {
          yield StreamError('Malformed streaming event: $e');
        }
      }
    }
  }

  void close() => _client.close();
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
