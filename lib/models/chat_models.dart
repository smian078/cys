import 'dart:convert';

class ChatAttachment {
  ChatAttachment({required this.id, required this.path, required this.name, required this.mimeType, required this.size, this.sourceUrl, this.sourceTitle});
  final String id;
  final String path;
  final String name;
  final String mimeType;
  final int size;
  final String? sourceUrl;
  final String? sourceTitle;

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'name': name, 'mimeType': mimeType, 'size': size, 'sourceUrl': sourceUrl, 'sourceTitle': sourceTitle};
  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: json['id'] as String,
        path: json['path'] as String,
        name: json['name'] as String,
        mimeType: json['mimeType'] as String,
        size: (json['size'] as num).toInt(),
        sourceUrl: json['sourceUrl'] as String?,
        sourceTitle: json['sourceTitle'] as String?,
      );
}

enum MessageRole { system, user, assistant, tool }

class ToolCallRecord {
  ToolCallRecord({required this.id, required this.name, required this.arguments, this.result, this.error, this.status = 'running'});
  final String id;
  final String name;
  final String arguments;
  final String? result;
  final String? error;
  final String status;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'arguments': arguments, 'result': result, 'error': error, 'status': status};
  factory ToolCallRecord.fromJson(Map<String, dynamic> json) => ToolCallRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        arguments: json['arguments'] as String,
        result: json['result'] as String?,
        error: json['error'] as String?,
        status: (json['status'] as String?) ?? 'running',
      );
}

class ChatMessage {
  ChatMessage({required this.id, required this.chatId, required this.role, required this.content, required this.createdAt, this.attachments = const [], this.reasoning = '', this.toolCalls = const [], this.model, this.responseId, this.tokens, this.latencyMs, this.usage, this.sources = const [], this.isError = false});
  final String id;
  final String chatId;
  final MessageRole role;
  String content;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  String reasoning;
  final List<ToolCallRecord> toolCalls;
  String? model;
  String? responseId;
  int? tokens;
  int? latencyMs;
  Map<String, dynamic>? usage;
  final List<SourceRecord> sources;
  bool isError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'reasoning': reasoning,
        'toolCalls': toolCalls.map((e) => e.toJson()).toList(),
        'model': model,
        'responseId': responseId,
        'tokens': tokens,
        'latencyMs': latencyMs,
        'usage': usage,
        'sources': sources.map((e) => e.toJson()).toList(),
        'isError': isError,
      };

  String dbJson() => jsonEncode(toJson());
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        chatId: json['chatId'] as String,
        role: MessageRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        attachments: ((json['attachments'] as List?) ?? const []).map((e) => ChatAttachment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        reasoning: (json['reasoning'] as String?) ?? '',
        toolCalls: ((json['toolCalls'] as List?) ?? const []).map((e) => ToolCallRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        model: json['model'] as String?,
        responseId: json['responseId'] as String?,
        tokens: (json['tokens'] as num?)?.toInt(),
        latencyMs: (json['latencyMs'] as num?)?.toInt(),
        usage: (json['usage'] as Map?)?.cast<String, dynamic>(),
        sources: ((json['sources'] as List?) ?? const []).map((e) => SourceRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        isError: (json['isError'] as bool?) ?? false,
      );
}

class SourceRecord {
  const SourceRecord({required this.title, required this.url, this.snippet, this.date});
  final String title;
  final String url;
  final String? snippet;
  final String? date;
  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'snippet': snippet, 'date': date};
  factory SourceRecord.fromJson(Map<String, dynamic> json) => SourceRecord(title: json['title'] as String, url: json['url'] as String, snippet: json['snippet'] as String?, date: json['date'] as String?);
}

class ChatSummary {
  ChatSummary({required this.id, required this.title, required this.createdAt, required this.updatedAt, this.pinned = false});
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  bool pinned;
}
