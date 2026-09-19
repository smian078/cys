import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import '../core/constants/model_constants.dart';

class GeminiResearchResult {
  const GeminiResearchResult({required this.text, required this.sources});
  final String text;
  final List<SourceRecord> sources;
}

class GeminiImageResult {
  const GeminiImageResult({required this.bytes, required this.mimeType, required this.sourceUrl, required this.title});
  final Uint8List bytes;
  final String mimeType;
  final String? sourceUrl;
  final String title;
}

class GeminiClient {
  GeminiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<GeminiResearchResult> research({required String apiKey, required String query, String model = ModelIds.geminiResearch}) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final response = await _client.post(uri, headers: {'x-goog-api-key': apiKey, 'Content-Type': 'application/json'}, body: jsonEncode({'contents': [{'parts': [{'text': query}]}], 'tools': [{'google_search': {}}]}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Gemini research failed ${response.statusCode}: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List? ?? const [];
    final content = candidates.isNotEmpty ? ((candidates.first as Map)['content'] as Map?) : null;
    final parts = (content?['parts'] as List?) ?? const [];
    final text = parts.map((p) => (p as Map)['text']).whereType<String>().join();
    final sources = <SourceRecord>[];
    final metadata = ((candidates.isNotEmpty ? (candidates.first as Map)['groundingMetadata'] : null) as Map?)?.cast<String, dynamic>();
    final chunks = metadata?['groundingChunks'];
    if (chunks is List) {
      for (final chunk in chunks) {
        final web = (chunk as Map)['web'] as Map?;
        if (web == null) continue;
        final url = web['uri'] as String?;
        final title = web['title'] as String?;
        if (url != null && title != null) sources.add(SourceRecord(title: title, url: url, snippet: web['snippet'] as String?));
      }
    }
    return GeminiResearchResult(text: text, sources: sources);
  }

  Future<List<GeminiImageResult>> imageSearch({required String apiKey, required String query, int maxCount = 6}) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/interactions');
    final response = await _client.post(uri, headers: {'x-goog-api-key': apiKey, 'Content-Type': 'application/json'}, body: jsonEncode({'model': ModelIds.geminiImage, 'input': query, 'tools': [{'type': 'google_search', 'search_types': ['image_search']}], 'response_format': [{'type': 'text'}, {'type': 'image'}]}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('Gemini image search failed ${response.statusCode}: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = <GeminiImageResult>[];
    final seen = <String>{};

    final directImage = data['output_image'];
    if (directImage is Map && directImage['data'] is String) {
      final bytes = base64Decode(directImage['data'] as String);
      final mime = (directImage['mime_type'] as String?) ?? 'image/png';
      results.add(GeminiImageResult(bytes: bytes, mimeType: mime, sourceUrl: null, title: query));
    }

    final steps = data['steps'];
    if (steps is List) {
      for (final step in steps) {
        final map = (step as Map).cast<String, dynamic>();
        if (map['type'] == 'model_output') {
          final content = map['content'];
          if (content is List) {
            for (final block in content) {
              final b = (block as Map).cast<String, dynamic>();
              if (b['type'] == 'image' && b['data'] is String) {
                final mime = (b['mime_type'] as String?) ?? 'image/png';
                final bytes = base64Decode(b['data'] as String);
                final sources = _sourcesFromAnnotations(b['annotations']);
                for (final source in sources) {
                  if (results.length >= maxCount) return results;
                  final downloaded = await _downloadImage(source, query);
                  if (downloaded == null) continue;
                  if (seen.add(source)) results.add(downloaded);
                }
                if (results.length < maxCount) {
                  final key = base64Encode(bytes.take(64).toList());
                  if (seen.add(key)) results.add(GeminiImageResult(bytes: bytes, mimeType: mime, sourceUrl: null, title: query));
                }
                if (results.length >= maxCount) return results;
              }
            }
          }
        }
      }
    }
    return results;
  }

  List<String> _sourcesFromAnnotations(dynamic annotations) {
    final sources = <String>[];
    if (annotations is List) {
      for (final item in annotations) {
        if (item is! Map) continue;
        final source = item['url'] ?? item['source'];
        if (source is String && source.startsWith('http') && !sources.contains(source)) sources.add(source);
      }
    }
    return sources;
  }

  Future<GeminiImageResult?> _downloadImage(String source, String title) async {
    try {
      final request = http.Request('GET', Uri.parse(source));
      request.headers['Accept'] = 'image/*';
      final response = await _client.send(request).timeout(const Duration(seconds: 12));
      final contentType = response.headers['content-type'] ?? '';
      final length = int.tryParse(response.headers['content-length'] ?? '');
      if (response.statusCode < 200 || response.statusCode >= 300 || !contentType.startsWith('image/') || (length != null && length > 8 * 1024 * 1024)) {
        await response.stream.drain();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.stream) {
        size += chunk.length;
        if (size > 8 * 1024 * 1024) return null;
        builder.add(chunk);
      }
      return GeminiImageResult(bytes: builder.takeBytes(), mimeType: contentType.split(';').first.trim(), sourceUrl: source, title: title);
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
