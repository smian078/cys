import 'chat_models.dart';

sealed class CystemStreamEvent {
  const CystemStreamEvent();
}

class TextDelta extends CystemStreamEvent {
  const TextDelta(this.text);
  final String text;
}

class ReasoningDelta extends CystemStreamEvent {
  const ReasoningDelta(this.text);
  final String text;
}

class ToolCallDelta extends CystemStreamEvent {
  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.arguments,
  });
  final int index;
  final String? id;
  final String? name;
  final String? arguments;
}

class ToolResultDelta extends CystemStreamEvent {
  const ToolResultDelta({
    required this.index,
    this.id,
    this.name,
    required this.result,
  });
  final int index;
  final String? id;
  final String? name;
  final String result;
}

class StreamFinished extends CystemStreamEvent {
  const StreamFinished({this.reason, this.responseId, this.model, this.usage});
  final String? reason;
  final String? responseId;
  final String? model;
  final Map<String, dynamic>? usage;
}

class StreamError extends CystemStreamEvent {
  const StreamError(this.message);
  final String message;
}

class SourceDelta extends CystemStreamEvent {
  const SourceDelta(this.source);
  final Map<String, dynamic> source;
}

class AttachmentDelta extends CystemStreamEvent {
  const AttachmentDelta(this.attachment);
  final ChatAttachment attachment;
}
