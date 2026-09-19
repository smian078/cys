import 'dart:async';
import 'dart:convert';
import '../app.dart';
import '../core/services/local_db.dart';
import '../core/constants/model_constants.dart';
import '../models/chat_models.dart';
import '../models/stream_events.dart';
import '../tools/tool_executor.dart';
import '../services/attachment_service.dart';
import 'gemini_client.dart';
import 'model_router.dart';
import 'nim_client.dart';

class PipelineRequest {
  const PipelineRequest({required this.message, required this.history, required this.attachments, required this.settings, this.forceWeb = false, this.forceImage = false});
  final String message;
  final List<ChatMessage> history;
  final List<ChatAttachment> attachments;
  final SettingsController settings;
  final bool forceWeb;
  final bool forceImage;
}

class PipelineCoordinator {
  PipelineCoordinator({NimClient? nim, GeminiClient? gemini, AttachmentService? attachments, ModelRouter? router, ToolExecutor? tools}) : _nim = nim ?? NimClient(), _gemini = gemini ?? GeminiClient(), _attachments = attachments, _router = router ?? ModelRouter(), _tools = tools;
  final NimClient _nim;
  final GeminiClient _gemini;
  final AttachmentService? _attachments;
  final ModelRouter _router;
  final ToolExecutor? _tools;

  Stream<CystemStreamEvent> run(PipelineRequest request, {required String? nvidiaKey, required String? geminiKey}) async* {
    final route = _router.route(prompt: request.message, forceWeb: request.forceWeb, forceImage: request.forceImage, selectedModel: request.settings.model);
    final brainModel = request.settings.model;
    var research = '';
    var sources = <SourceRecord>[];
    if ((route.useWeb || route.useImages) && geminiKey != null && geminiKey.isNotEmpty) {
      if (route.useWeb) {
        try {
          final result = await _gemini.research(apiKey: geminiKey, query: request.message);
          research = result.text;
          sources = result.sources;
          for (final source in sources) yield SourceDelta(source.toJson());
        } catch (e) {
          yield StreamError('Web research failed: $e');
        }
      } else {
        try {
          final images = await _gemini.imageSearch(apiKey: geminiKey, query: request.message);
          research = 'Image search returned ${images.length} image result(s).\n';
          if (_attachments != null) {
            for (var i = 0; i < images.length; i++) {
              final image = images[i];
              final saved = await _attachments!.persistBytes(image.bytes, name: 'image_${i + 1}.png', mimeType: image.mimeType, sourceUrl: image.sourceUrl, sourceTitle: image.title);
              yield AttachmentDelta(saved);
              research += 'Image: ${image.title}${image.sourceUrl == null ? '' : '\nSource: ${image.sourceUrl}'}\n';
            }
          }
        } catch (e) {
          yield StreamError('Image search failed: $e');
        }
      }
    }

    if (nvidiaKey == null || nvidiaKey.isEmpty) {
      yield const StreamError('Add an NVIDIA API key in Settings → Providers to use the main brain.');
      return;
    }

    final analyzedAttachments = <Map<String, dynamic>>[];
    if (_attachments != null && request.attachments.isNotEmpty) {
      for (final attachment in request.attachments) {
        final context = await _attachments!.buildContext(attachment);
        final analysis = await _analyzeAttachment(context: context, apiKey: nvidiaKey! , baseUrl: request.settings.nvidiaBaseUrl, effort: request.settings.reasoningEffort);
        analyzedAttachments.add({'name': attachment.name, 'mime': attachment.mimeType, 'analysis': analysis});
      }
    }

    final system = """You are CYSTEM, a private personal AI command center. The main brain is responsible for the user-facing final answer. Use supplied research and attachment analysis as factual context, but do not pretend to have performed actions you did not perform. Be concise unless the user needs detail. Respect the user's custom system instructions.\n\nCustom instructions:\n${request.settings.systemInstructions}""";
    final memoryRows = request.settings.memoryEnabled ? await LocalDb.instance.memories() : const <Map<String, Object?>>[];
    final memoryText = memoryRows.where((m) => (m['enabled'] as int? ?? 0) == 1).map((m) => '${m['key']}: ${m['value']}').join('\n');
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': '$system${memoryText.isEmpty ? '' : '\n\nOn-device memory:\n$memoryText'}'},
      ...request.history.takeLast(30).map((m) => {'role': m.role.name, 'content': m.content}),
    ];
    if (research.isNotEmpty || analyzedAttachments.isNotEmpty) {
      messages.add({'role': 'system', 'content': 'Context gathered by CYSTEM services:\n${research.isEmpty ? '' : 'WEB RESEARCH:\n$research\n'}${analyzedAttachments.isEmpty ? '' : 'ATTACHMENTS:\n${jsonEncode(analyzedAttachments)}'}'});
    }
    messages.add({'role': 'user', 'content': request.message});

    final toolDefinitions = _tools == null ? <Map<String, dynamic>>[] : _tools!.registry.openAiDefinitions();
    final baseUrl = request.settings.nvidiaBaseUrl.replaceFirst(RegExp(r'/$'), '');
    for (var turn = 0; turn < 6; turn++) {
      final pendingTools = <int, _ToolAccumulator>{};
      var toolArgumentsReady = false;
      StreamFinished? finished;
      await for (final event in _nim.stream(
        baseUrl: baseUrl,
        apiKey: nvidiaKey,
        model: brainModel,
        messages: messages,
        tools: toolDefinitions,
        seed: request.settings.seed,
        reasoningEffort: request.settings.reasoningEffort,
      )) {
        if (event is ToolCallDelta) {
          final acc = pendingTools.putIfAbsent(event.index, () => _ToolAccumulator());
          if (event.id != null) acc.id = event.id;
          if (event.name != null) acc.name = event.name;
          if (event.arguments != null) acc.arguments.write(event.arguments!);
          if (acc.name != null && acc.arguments.isNotEmpty) toolArgumentsReady = true;
          yield event;
        } else if (event is StreamFinished) {
          finished = event;
        } else {
          yield event;
        }
      }

      if (toolArgumentsReady && _tools != null) {
        final assistantCalls = pendingTools.entries
            .where((e) => e.value.name != null)
            .map((e) => {
                  'id': e.value.id ?? 'call_${e.key}',
                  'type': 'function',
                  'function': {
                    'name': e.value.name,
                    'arguments': e.value.arguments.toString(),
                  },
                })
            .toList();
        if (assistantCalls.isEmpty) {
          if (finished != null) yield finished;
          return;
        }
        messages.add({'role': 'assistant', 'content': '', 'tool_calls': assistantCalls});
        for (final entry in pendingTools.entries.where((e) => e.value.name != null)) {
          final result = await _tools.execute(entry.value.name!, entry.value.arguments.toString());
          yield ToolResultDelta(
            index: entry.key,
            id: entry.value.id ?? 'call_${entry.key}',
            name: entry.value.name,
            result: result,
          );
          messages.add({
            'role': 'tool',
            'content': result,
            'tool_call_id': entry.value.id ?? 'call_${entry.key}',
          });
        }
        continue;
      }

      if (finished != null) yield finished;
      return;
    }
    yield const StreamError('Tool execution exceeded the maximum continuation depth.');
  }

  Future<String> _analyzeAttachment({required AttachmentContext context, required String apiKey, required String baseUrl, required String effort}) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': 'Analyze this attachment for factual context only. Extract visible text, objects, people, UI elements, charts, colors, spatial relationships, and important details. Do not answer the end user directly. Return concise factual notes.'},
    ];
    if (context.imageDataUri != null) {
      content.add({'type': 'image_url', 'image_url': {'url': context.imageDataUri}});
    } else if (context.extractedText != null) {
      content[0]['text'] = '${content[0]['text']}\n\nFILE CONTENT:\n${context.extractedText}';
    }
    final out = StringBuffer();
    await for (final event in _nim.stream(baseUrl: baseUrl.replaceFirst(RegExp(r'/$'), ''), apiKey: apiKey, model: ModelIds.nemotronNanoOmni, messages: [
      {'role': 'user', 'content': content}
    ], reasoningEffort: effort, temperature: 0.6, topP: 0.95)) {
      if (event is TextDelta) out.write(event.text);
      if (event is StreamError) out.write('Attachment analysis error: ${event.message}');
    }
    return out.toString();
  }
}

class _ToolAccumulator { String? id; String? name; final StringBuffer arguments = StringBuffer(); }

extension _TakeLast<T> on List<T> { List<T> takeLast(int count) => length <= count ? this : sublist(length - count); }
