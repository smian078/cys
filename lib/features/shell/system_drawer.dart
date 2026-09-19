import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../models/chat_models.dart';
import '../../core/services/local_db.dart';
import '../../services/cystem_services.dart';
import '../settings/settings_screen.dart';

class SystemDrawer extends ConsumerStatefulWidget {
  const SystemDrawer({super.key});

  @override
  ConsumerState<SystemDrawer> createState() => _SystemDrawerState();
}

class _SystemDrawerState extends ConsumerState<SystemDrawer> {
  final search = TextEditingController();
  List<ChatSummary> chats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await LocalDb.instance.db.query(
      'chats',
      orderBy: 'pinned DESC, updated_at DESC',
    );
    if (!mounted) return;
    setState(() {
      chats = rows
          .map(
            (row) => ChatSummary(
              id: row['id'] as String,
              title: row['title'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row['created_at'] as int,
              ),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                row['updated_at'] as int,
              ),
              pinned: row['pinned'] as int == 1,
            ),
          )
          .toList();
    });
  }

  Future<void> _newChat() async {
    final id = 'drawer_new_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    await LocalDb.instance.db.insert('chats', {
      'id': id,
      'title': 'New CYSTEM session',
      'created_at': now,
      'updated_at': now,
      'pinned': 0,
    });
    ref.read(currentChatIdProvider.notifier).state = id;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _togglePin(ChatSummary chat) async {
    await LocalDb.instance.db.update(
      'chats',
      {'pinned': chat.pinned ? 0 : 1},
      where: 'id=?',
      whereArgs: [chat.id],
    );
    await _load();
  }

  Future<void> _deleteChat(ChatSummary chat) async {
    await LocalDb.instance.db.delete(
      'attachments',
      where: 'chat_id=?',
      whereArgs: [chat.id],
    );
    await LocalDb.instance.db.delete(
      'messages',
      where: 'chat_id=?',
      whereArgs: [chat.id],
    );
    await LocalDb.instance.db.delete(
      'chats',
      where: 'id=?',
      whereArgs: [chat.id],
    );
    if (ref.read(currentChatIdProvider) == chat.id) {
      ref.read(currentChatIdProvider.notifier).state = null;
    }
    await _load();
  }

  Future<void> _renameChat(ChatSummary chat) async {
    final controller = TextEditingController(text: chat.title);
    final renamed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = renamed?.trim();
    if (title == null || title.isEmpty) return;
    await LocalDb.instance.db.update(
      'chats',
      {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id=?',
      whereArgs: [chat.id],
    );
    await _load();
  }

  Future<void> _export() async {
    final raw = await LocalDb.instance.exportJson();
    final dir = await LocalDb.instance.attachmentsDirectory();
    final file = File(
      '${dir.parent.path}/cystem_backup_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(raw);
    await CystemServices.instance.android.shareFile(file.path);
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = file?.path;
    if (path == null) return;
    try {
      final raw = await File(path).readAsString();
      await LocalDb.instance.importJson(raw);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  String _age(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? chats
        : chats
              .where((chat) => chat.title.toLowerCase().contains(query))
              .toList();
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: scheme.surface.withValues(alpha: .94),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.memory, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'CYSTEM',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close sessions',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search chats',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: FilledButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add),
                label: const Text('NEW SYSTEM SESSION'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  return ListTile(
                    leading: Icon(
                      chat.pinned ? Icons.push_pin : Icons.chat_bubble_outline,
                    ),
                    title: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_age(chat.updatedAt)),
                    onTap: () {
                      ref.read(currentChatIdProvider.notifier).state = chat.id;
                      Navigator.pop(context);
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'pin':
                            await _togglePin(chat);
                            break;
                          case 'rename':
                            await _renameChat(chat);
                            break;
                          case 'delete':
                            await _deleteChat(chat);
                            break;
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'pin', child: Text('Pin / unpin')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Export backup'),
              onTap: _export,
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Import backup'),
              onTap: _import,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
