import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();
  static final instance = SecureStore._();
  static const _nvidia = 'cystem.nvidia.key';
  static const _gemini = 'cystem.gemini.key';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> readNvidia() => _storage.read(key: _nvidia);
  Future<String?> readGemini() => _storage.read(key: _gemini);
  Future<void> saveNvidia(String value) =>
      _storage.write(key: _nvidia, value: value.trim());
  Future<void> saveGemini(String value) =>
      _storage.write(key: _gemini, value: value.trim());
  Future<void> deleteNvidia() => _storage.delete(key: _nvidia);
  Future<void> deleteGemini() => _storage.delete(key: _gemini);
}
