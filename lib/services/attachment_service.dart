import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../core/services/local_db.dart';
import '../models/chat_models.dart';

class AttachmentService {
  AttachmentService(this._db);
  final LocalDb _db;
  final _uuid = const Uuid();

  Future<List<ChatAttachment>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null) return [];
    return Future.wait(result.files.where((f) => f.path != null).map((f) => persist(File(f.path!), displayName: f.name)));
  }

  Future<ChatAttachment?> captureCamera() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (picked == null) return null;
    return persist(File(picked.path), displayName: p.basename(picked.path));
  }

  Future<ChatAttachment> persist(File source, {String? displayName, String? sourceUrl, String? sourceTitle}) async {
    final dir = await _db.attachmentsDirectory();
    final mime = lookupMimeType(source.path) ?? 'application/octet-stream';
    final id = _uuid.v4();
    final extension = p.extension(source.path);
    final target = File(p.join(dir.path, '$id$extension'));
    await source.copy(target.path);
    final size = await target.length();
    return ChatAttachment(id: id, path: target.path, name: displayName ?? p.basename(source.path), mimeType: mime, size: size, sourceUrl: sourceUrl, sourceTitle: sourceTitle);
  }


  Future<ChatAttachment> persistBytes(List<int> bytes, {required String name, required String mimeType, String? sourceUrl, String? sourceTitle}) async {
    final dir = await _db.attachmentsDirectory();
    final id = _uuid.v4();
    final extension = p.extension(name).isNotEmpty ? p.extension(name) : '.bin';
    final target = File(p.join(dir.path, '$id$extension'));
    await target.writeAsBytes(bytes, flush: true);
    return ChatAttachment(id: id, path: target.path, name: name, mimeType: mimeType, size: bytes.length, sourceUrl: sourceUrl, sourceTitle: sourceTitle);
  }

  Future<AttachmentContext> buildContext(ChatAttachment attachment) async {
    final file = File(attachment.path);
    final bytes = await file.readAsBytes();
    if (attachment.mimeType.startsWith('image/')) {
      return AttachmentContext(attachment: attachment, imageDataUri: 'data:${attachment.mimeType};base64,${base64Encode(bytes)}');
    }
    if (attachment.mimeType == 'application/pdf' || p.extension(attachment.path).toLowerCase() == '.pdf') {
      final document = PdfDocument(inputBytes: bytes);
      final extracted = PdfTextExtractor(document).extractText();
      document.dispose();
      return AttachmentContext(
        attachment: attachment,
        extractedText: extracted.length > 120000 ? extracted.substring(0, 120000) : extracted,
      );
    }
    if (_isTextLike(attachment.mimeType, attachment.path)) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return AttachmentContext(attachment: attachment, extractedText: text.length > 120000 ? text.substring(0, 120000) : text);
    }
    return AttachmentContext(attachment: attachment, extractedText: 'File: ${attachment.name}\nMIME: ${attachment.mimeType}\nSize: ${attachment.size} bytes. Binary extraction is not available for this type; analyze only available metadata.');
  }

  bool _isTextLike(String mime, String path) {
    if (mime.startsWith('text/')) return true;
    const exts = {'.md', '.json', '.csv', '.log', '.xml', '.yaml', '.yml', '.dart', '.kt', '.java', '.gradle', '.txt'};
    return exts.contains(p.extension(path).toLowerCase());
  }
}

class AttachmentContext {
  const AttachmentContext({required this.attachment, this.imageDataUri, this.extractedText});
  final ChatAttachment attachment;
  final String? imageDataUri;
  final String? extractedText;
}
