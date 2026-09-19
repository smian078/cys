import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../core/services/local_db.dart';
import '../../core/services/platform_bridge.dart';
import '../../core/services/secure_store.dart';
import '../../models/chat_models.dart';
import '../../models/stream_events.dart';
import '../../services/cystem_services.dart';
import '../../services/pipeline_coordinator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.hostScaffoldKey});
  final GlobalKey<ScaffoldState> hostScaffoldKey;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final text = TextEditingController();
  final scroll = ScrollController();
  final uuid = const Uuid();
  final tts = FlutterTts();
  final speech = stt.SpeechToText();
  final messages = <ChatMessage>[];
  final attachments = <ChatAttachment>[];
  StreamSubscription<CystemStreamEvent>? active;
  StreamSubscription<SharedPayload>? shareSubscription;
  bool thinking = false;
  bool speaking = false;
  bool listening = false;
  bool forceWeb = false;
  bool forceImage = false;
  String? chatId;

  @override
  void initState() {
    super.initState();
    _startChat();
    shareSubscription = CystemServices.instance.android.sharedPayloads.listen(
      _consumeShare,
    );
  }

  Future<void> _startChat() async {
    chatId = ref.read(currentChatIdProvider) ?? uuid.v4();
    ref.read(currentChatIdProvider.notifier).state = chatId;
    await _ensureChat();
    final shared = await CystemServices.instance.android.initialShare();
    if (shared != null) await _consumeShare(shared);
  }

  Future<void> _loadExistingChat(String id) async {
    final rows = await LocalDb.instance.db.query(
      'messages',
      where: 'chat_id=?',
      whereArgs: [id],
      orderBy: 'created_at ASC',
    );
    final loaded = rows.map((r) {
      try {
        return ChatMessage.fromJson(
          jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        );
      } catch (_) {
        return ChatMessage(
          id: r['id'] as String,
          chatId: id,
          role: MessageRole.values.byName(r['role'] as String),
          content: r['content'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            r['created_at'] as int,
          ),
        );
      }
    }).toList();
    if (!mounted) return;
    setState(() {
      chatId = id;
      messages
        ..clear()
        ..addAll(loaded);
      attachments.clear();
    });
    _scrollToBottom();
  }

  Future<void> _consumeShare(SharedPayload payload) async {
    if (payload.text.isNotEmpty) {
      text.text = payload.text;
    }
    for (final path in payload.paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final attachment = await CystemServices.instance.attachmentService
          .persist(file, displayName: path.split('/').last);
      if (mounted) setState(() => attachments.add(attachment));
    }
  }

  Future<void> _ensureChat() async {
    final existing = await LocalDbBridge.chatRows(chatId!);
    if (existing == null) await LocalDbBridge.createChat(chatId!);
  }

  @override
  void dispose() {
    active?.cancel();
    shareSubscription?.cancel();
    text.dispose();
    scroll.dispose();
    tts.stop();
    speech.stop();
    super.dispose();
  }

  Future<void> send() async {
    final prompt = text.text.trim();
    if (prompt.isEmpty && attachments.isEmpty) return;
    if (prompt.startsWith('/')) {
      _applySlash(prompt);
      return;
    }

    final id = chatId!;
    final requestAttachments = List<ChatAttachment>.of(attachments);
    final user = ChatMessage(
      id: uuid.v4(),
      chatId: id,
      role: MessageRole.user,
      content: prompt,
      createdAt: DateTime.now(),
      attachments: requestAttachments,
    );
    messages.add(user);
    await LocalDbBridge.saveMessage(user);

    text.clear();
    final assistant = ChatMessage(
      id: uuid.v4(),
      chatId: id,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );
    messages.add(assistant);
    setState(() {
      thinking = true;
      attachments.clear();
    });
    _scrollToBottom();

    final settings = ref.read(settingsProvider);
    final nvidia = await SecureStore.instance.readNvidia();
    final gemini = await SecureStore.instance.readGemini();
    final history = messages.where((m) => m.id != assistant.id).toList();
    final request = PipelineRequest(
      message: prompt.isEmpty ? 'Analyze the attached content.' : prompt,
      history: history,
      attachments: requestAttachments,
      settings: settings,
      forceWeb: forceWeb,
      forceImage: forceImage,
    );
    final toolBuffers = <int, _ToolDraft>{};
    final started = DateTime.now();
    forceWeb = false;
    forceImage = false;

    active = CystemServices.instance.pipeline
        .run(request, nvidiaKey: nvidia, geminiKey: gemini)
        .listen(
          (event) async {
            if (!mounted) return;
            if (event is TextDelta) {
              assistant.content += event.text;
            } else if (event is ReasoningDelta) {
              assistant.reasoning += event.text;
            } else if (event is SourceDelta) {
              assistant.sources.add(
                SourceRecord(
                  title: event.source['title'] as String? ?? 'Source',
                  url: event.source['url'] as String? ?? '',
                  snippet: event.source['snippet'] as String?,
                  date: event.source['date'] as String?,
                ),
              );
            } else if (event is AttachmentDelta) {
              assistant.attachments.add(event.attachment);
            } else if (event is ToolCallDelta) {
              final draft = toolBuffers.putIfAbsent(
                event.index,
                _ToolDraft.new,
              );
              if (event.id != null) draft.id = event.id!;
              if (event.name != null) draft.name = event.name!;
              if (event.arguments != null) {
                draft.arguments.write(event.arguments!);
              }
            } else if (event is ToolResultDelta) {
              final draft = toolBuffers.putIfAbsent(
                event.index,
                _ToolDraft.new,
              );
              draft.id = event.id ?? draft.id;
              draft.name = event.name ?? draft.name;
              draft.result = event.result;
            } else if (event is StreamFinished) {
              for (final draft in toolBuffers.values) {
                if (draft.name == null) continue;
                assistant.toolCalls.add(
                  ToolCallRecord(
                    id: draft.id ?? uuid.v4(),
                    name: draft.name!,
                    arguments: draft.arguments.toString(),
                    result: draft.result,
                    status: draft.result?.contains('"ok":false') == true
                        ? 'failed'
                        : 'success',
                  ),
                );
              }
              assistant.model = event.model ?? settings.model;
              assistant.responseId = event.responseId;
              assistant.tokens = (event.usage?['total_tokens'] as num?)
                  ?.toInt();
              assistant.usage = event.usage;
              assistant.latencyMs = DateTime.now()
                  .difference(started)
                  .inMilliseconds;
              setState(() => thinking = false);
              await LocalDbBridge.saveMessage(assistant);
              await _speak(assistant.content);
            } else if (event is StreamError) {
              assistant.isError = true;
              assistant.content += assistant.content.isEmpty
                  ? event.message
                  : '\n\n${event.message}';
              setState(() => thinking = false);
              await LocalDbBridge.saveMessage(assistant);
            }
            if (mounted) {
              setState(() {});
              _scrollToBottom();
            }
          },
          onDone: () {
            if (mounted) setState(() => thinking = false);
          },
        );
  }

  void _applySlash(String cmd) {
    final parts = cmd.split(RegExp(r'\s+'));
    switch (parts.first) {
      case '/search':
        forceWeb = true;
        text.text = parts.skip(1).join(' ');
        break;
      case '/image':
        forceImage = true;
        text.text = parts.skip(1).join(' ');
        break;
      case '/new':
        _newChat();
        break;
      case '/model':
        if (parts.length > 1) ref.read(settingsProvider).updateModel(parts[1]);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commands: /search, /image, /model, /new'),
          ),
        );
    }
  }

  void _newChat() {
    final id = uuid.v4();
    setState(() {
      messages.clear();
      attachments.clear();
      chatId = id;
    });
    LocalDbBridge.createChat(id);
    ref.read(currentChatIdProvider.notifier).state = id;
    Navigator.of(context).maybePop();
  }

  Future<void> _editAndResend(ChatMessage message) async {
    final index = messages.indexOf(message);
    if (index < 0) return;
    final ids = messages.sublist(index).map((m) => m.id).toList();
    await LocalDbBridge.deleteMessages(ids);
    setState(() {
      messages.removeRange(index, messages.length);
      text.text = message.content;
    });
    await send();
  }

  Future<void> pickFiles() async {
    final picked = await CystemServices.instance.attachmentService.pickFiles();
    if (mounted) setState(() => attachments.addAll(picked));
  }

  Future<void> camera() async {
    final attachment = await CystemServices.instance.attachmentService
        .captureCamera();
    if (attachment != null && mounted) {
      setState(() => attachments.add(attachment));
    }
  }

  Future<void> toggleMic() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    final ready = await speech.initialize();
    if (!ready) return;
    if (mounted) setState(() => listening = true);
    await speech.listen(
      onResult: (result) {
        if (mounted) setState(() => text.text = result.recognizedWords);
      },
    );
  }

  Future<void> _speak(String value) async {
    if (value.trim().isEmpty) return;
    tts.setCompletionHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    if (mounted) setState(() => speaking = true);
    await tts.speak(value.replaceAll(RegExp(r'[`*_#>]'), ''));
  }

  void stop() {
    active?.cancel();
    if (mounted) setState(() => thinking = false);
  }

  void _showDetails(ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REPLY DETAILS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              _DetailRow('Model', message.model ?? 'Unknown'),
              _DetailRow('Response ID', message.responseId ?? '—'),
              _DetailRow('Tokens', message.tokens?.toString() ?? '—'),
              _DetailRow(
                'Latency',
                message.latencyMs == null ? '—' : '${message.latencyMs} ms',
              ),
              _DetailRow('Sources', message.sources.length.toString()),
              _DetailRow('Tool calls', message.toolCalls.length.toString()),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    if (!scroll.hasClients) return;
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(currentChatIdProvider, (previous, next) {
      if (next != null && next != chatId) _loadExistingChat(next);
    });
    final selectedChat = ref.watch(currentChatIdProvider);
    if (selectedChat != null && selectedChat != chatId) {
      Future<void>.microtask(() => _loadExistingChat(selectedChat));
    }
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      drawerEnableOpenDragGesture: true,
      body: Stack(
        children: [
          _Backdrop(accent: Theme.of(context).colorScheme.primary),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  onMenu: () =>
                      widget.hostScaffoldKey.currentState?.openDrawer(),
                ),
                Expanded(
                  child: messages.isEmpty
                      ? _EmptyState(
                          onPrompt: (prompt) {
                            text.text = prompt;
                            send();
                          },
                        )
                      : ListView.builder(
                          controller: scroll,
                          padding: EdgeInsets.fromLTRB(
                            width > 700 ? 80 : 14,
                            10,
                            width > 700 ? 80 : 14,
                            150,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final message = messages[i];
                            return _MessageCard(
                              message: message,
                              streaming:
                                  thinking &&
                                  i == messages.length - 1 &&
                                  message.role == MessageRole.assistant,
                              onSpeak: () => _speak(message.content),
                              onCopy: () => CystemServices.instance.android
                                  .shareText(message.content),
                              onDetails: () => _showDetails(message),
                              onEdit: message.role == MessageRole.user
                                  ? () => _editAndResend(message)
                                  : null,
                            );
                          },
                        ),
                ),
                if (attachments.isNotEmpty)
                  _AttachmentStrip(
                    attachments: attachments,
                    onRemove: (attachment) =>
                        setState(() => attachments.remove(attachment)),
                  ),
                _Composer(
                  text: text,
                  thinking: thinking,
                  listening: listening,
                  speaking: speaking,
                  forceWeb: forceWeb,
                  forceImage: forceImage,
                  onSend: send,
                  onStop: stop,
                  onFiles: pickFiles,
                  onCamera: camera,
                  onMic: toggleMic,
                  onWeb: () => setState(() => forceWeb = !forceWeb),
                  onImage: () => setState(() => forceImage = !forceImage),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolDraft {
  String? id;
  String? name;
  String? result;
  final StringBuffer arguments = StringBuffer();
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onMenu});
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(
      children: [
        IconButton(
          onPressed: onMenu,
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Open sessions',
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CYSTEM',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            Text(
              'PERSONAL OS • ONLINE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text('CORE READY', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _GridPainter(accent), size: Size.infinite),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = accent.withValues(alpha: .07);
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPrompt});
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: .35),
                  Colors.transparent,
                ],
              ),
            ),
            child: Icon(
              Icons.hub_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'SYSTEM ONLINE',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask, attach, search, command. CYSTEM routes the work and returns the result.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children:
                [
                      'Explain something deeply',
                      'Search the latest AI news',
                      'Analyze this image',
                      'Plan my week',
                    ]
                    .map(
                      (prompt) => ActionChip(
                        label: Text(prompt),
                        onPressed: () => onPrompt(prompt),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.streaming,
    required this.onSpeak,
    required this.onCopy,
    required this.onDetails,
    this.onEdit,
  });
  final ChatMessage message;
  final bool streaming;
  final VoidCallback onSpeak;
  final VoidCallback onCopy;
  final VoidCallback onDetails;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final mine = message.role == MessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: RepaintBoundary(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: mine
                ? scheme.primary.withValues(alpha: .16)
                : scheme.surface.withValues(alpha: .68),
            border: Border.all(
              color: mine
                  ? scheme.primary.withValues(alpha: .24)
                  : scheme.outlineVariant.withValues(alpha: .25),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: mine ? .05 : .025),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    mine ? Icons.person_outline : Icons.memory_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    mine ? 'YOU' : 'CYSTEM',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (mine && onEdit != null)
                    IconButton(
                      tooltip: 'Edit and resend',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  if (!mine) ...[
                    IconButton(
                      tooltip: 'Read aloud',
                      onPressed: onSpeak,
                      icon: const Icon(Icons.volume_up_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Copy/share',
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Reply details',
                      onPressed: onDetails,
                      icon: const Icon(Icons.info_outline, size: 18),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (message.reasoning.isNotEmpty && !mine)
                ExpansionTile(
                  title: const Text('REASONING'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    SelectableText(
                      message.reasoning,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              if (message.toolCalls.isNotEmpty && !mine) ...[
                for (final tool in message.toolCalls) _ToolCallCard(tool: tool),
                const SizedBox(height: 8),
              ],
              if (message.attachments.isNotEmpty)
                _AttachmentStrip(attachments: message.attachments),
              MarkdownBody(
                data:
                    '${message.content.isEmpty ? '…' : message.content}${streaming ? ' ▌' : ''}',
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                      code: const TextStyle(fontFamily: 'monospace'),
                    ),
              ),
              if (message.sources.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: message.sources
                      .where((source) => source.url.isNotEmpty)
                      .take(8)
                      .map(
                        (source) => InputChip(
                          label: Text(
                            source.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => CystemServices.instance.android
                              .openUrl(source.url),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (message.isError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'REQUEST ERROR',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.tool});
  final ToolCallRecord tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.build_circle_outlined,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(child: Text(tool.name)),
              Text(
                tool.status.toUpperCase(),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tool.arguments,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          if (tool.result != null) ...[
            const SizedBox(height: 6),
            Text(
              'RESULT',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(letterSpacing: 1.0),
            ),
            Text(
              tool.result!,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({required this.attachments, this.onRemove});
  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment>? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 74,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: attachments.length,
      itemBuilder: (context, i) {
        final attachment = attachments[i];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 120,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              ),
              child: Row(
                children: [
                  if (attachment.mimeType.startsWith('image/'))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.file(
                        File(attachment.path),
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined, size: 20),
                      ),
                    )
                  else
                    const Icon(Icons.insert_drive_file_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      attachment.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              Positioned(
                right: -4,
                top: -4,
                child: IconButton(
                  onPressed: () => onRemove!(attachment),
                  icon: const Icon(Icons.cancel, size: 18),
                  tooltip: 'Remove attachment',
                ),
              ),
          ],
        );
      },
      separatorBuilder: (_, _) => const SizedBox(width: 8),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.text,
    required this.thinking,
    required this.listening,
    required this.speaking,
    required this.forceWeb,
    required this.forceImage,
    required this.onSend,
    required this.onStop,
    required this.onFiles,
    required this.onCamera,
    required this.onMic,
    required this.onWeb,
    required this.onImage,
  });
  final TextEditingController text;
  final bool thinking;
  final bool listening;
  final bool speaking;
  final bool forceWeb;
  final bool forceImage;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onFiles;
  final VoidCallback onCamera;
  final VoidCallback onMic;
  final VoidCallback onWeb;
  final VoidCallback onImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .90),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .25)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Files',
                  onPressed: onFiles,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  tooltip: 'Camera',
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                IconButton(
                  tooltip: 'Voice input',
                  onPressed: onMic,
                  icon: Icon(listening ? Icons.mic : Icons.mic_none),
                ),
                FilterChip(
                  selected: forceWeb,
                  onSelected: (_) => onWeb(),
                  label: const Text('/search'),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  selected: forceImage,
                  onSelected: (_) => onImage(),
                  label: const Text('/image'),
                ),
                const Spacer(),
                if (listening) const _Waveform(),
                if (speaking) Icon(Icons.volume_up, color: scheme.primary),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) => thinking ? null : onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Command the system…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: thinking
                      ? IconButton.filled(
                          onPressed: onStop,
                          tooltip: 'Stop generation',
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.filled(
                          onPressed: onSend,
                          tooltip: 'Send',
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform();

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 22,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (index) {
          final phase = (controller.value + index * .16) % 1;
          final height = 6 + 14 * (0.5 + 0.5 * (1 - (phase - .5).abs() * 2));
          return Container(
            width: 4,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    ),
  );
}

class LocalDbBridge {
  static Future<Map<String, Object?>?> chatRows(String id) async {
    final rows = await LocalDb.instance.db.query(
      'chats',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<void> createChat(String id) async {
    await LocalDb.instance.db.insert('chats', {
      'id': id,
      'title': 'New CYSTEM session',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'pinned': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> saveMessage(ChatMessage message) async {
    await LocalDb.instance.db.transaction((txn) async {
      await txn.insert('messages', {
        'id': message.id,
        'chat_id': message.chatId,
        'role': message.role.name,
        'content': message.content,
        'created_at': message.createdAt.millisecondsSinceEpoch,
        'payload': message.dbJson(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final attachment in message.attachments) {
        await txn.insert('attachments', {
          'id': attachment.id,
          'chat_id': message.chatId,
          'message_id': message.id,
          'path': attachment.path,
          'name': attachment.name,
          'mime': attachment.mimeType,
          'size': attachment.size,
          'source_url': attachment.sourceUrl,
          'source_title': attachment.sourceTitle,
          'created_at': message.createdAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update(
        'chats',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id=?',
        whereArgs: [message.chatId],
      );
    });
  }

  static Future<void> deleteMessages(List<String> ids) async {
    if (ids.isEmpty) return;
    await LocalDb.instance.db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('attachments', where: 'message_id=?', whereArgs: [id]);
        await txn.delete('messages', where: 'id=?', whereArgs: [id]);
      }
    });
  }
}
