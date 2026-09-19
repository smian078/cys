import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'backup_codec.dart';

class LocalDb {
  LocalDb._();
  static final instance = LocalDb._();
  Database? _db;

  Database get db => _db!;

  Future<void> open() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'cystem.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE chats(id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0)');
      await db.execute('CREATE TABLE messages(id TEXT PRIMARY KEY, chat_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL, payload TEXT NOT NULL, FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE memories(id TEXT PRIMARY KEY, key TEXT NOT NULL, value TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL)');
      await db.execute('CREATE TABLE attachments(id TEXT PRIMARY KEY, chat_id TEXT NOT NULL, message_id TEXT, path TEXT NOT NULL, name TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER NOT NULL, source_url TEXT, source_title TEXT, created_at INTEGER NOT NULL)');
      await db.execute('CREATE INDEX messages_chat_idx ON messages(chat_id, created_at)');
      await db.execute('CREATE INDEX attachments_chat_idx ON attachments(chat_id)');
    });
  }

  Future<List<Map<String, Object?>>> memories() => db.query('memories', orderBy: 'updated_at DESC');

  Future<void> upsertMemory(String id, String key, String value, bool enabled) async { await db.insert('memories', {'id': id, 'key': key, 'value': value, 'enabled': enabled ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace); }

  Future<void> deleteMemory(String id) => db.delete('memories', where: 'id=?', whereArgs: [id]);

  Future<void> clearAll() async {
    await db.delete('attachments');
    await db.delete('messages');
    await db.delete('chats');
    await db.delete('memories');
  }

  Map<String, dynamic> rowPayload(String payload) => jsonDecode(payload) as Map<String, dynamic>;
  static const _backupCodec = BackupCodec();
  Future<String> exportJson() async {
    final chats = await db.query('chats', orderBy: 'updated_at DESC');
    final messages = await db.query('messages', orderBy: 'created_at ASC');
    final memories = await db.query('memories', orderBy: 'updated_at ASC');
    final attachments = await db.query('attachments', orderBy: 'created_at ASC');
    return _backupCodec.encode(chats: chats, messages: messages, memories: memories, attachments: attachments);
  }

  Future<void> importJson(String raw) async {
    final data = _backupCodec.decode(raw);
    await db.transaction((txn) async {
      for (final table in ['attachments', 'messages', 'memories', 'chats']) {
        await txn.delete(table);
      }
      for (final row in (data['chats'] as List? ?? const [])) await txn.insert('chats', Map<String, Object?>.from(row as Map));
      for (final row in (data['messages'] as List? ?? const [])) await txn.insert('messages', Map<String, Object?>.from(row as Map));
      for (final row in (data['memories'] as List? ?? const [])) await txn.insert('memories', Map<String, Object?>.from(row as Map));
      for (final row in (data['attachments'] as List? ?? const [])) await txn.insert('attachments', Map<String, Object?>.from(row as Map));
    });
  }

  Future<Directory> attachmentsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'attachments'));
    await dir.create(recursive: true);
    return dir;
  }
}
