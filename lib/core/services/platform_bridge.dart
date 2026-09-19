import 'dart:async';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class AndroidBridge {
  static const _channel = MethodChannel('cystem/android');
  final _sharedController = StreamController<SharedPayload>.broadcast();
  Stream<SharedPayload> get sharedPayloads => _sharedController.stream;

  AndroidBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareIntent') {
        _sharedController.add(
          SharedPayload.fromMap(
            Map<String, dynamic>.from(call.arguments as Map),
          ),
        );
      }
    });
  }

  Future<SharedPayload?> initialShare() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getInitialShare',
    );
    if (result == null) return null;
    final value = SharedPayload.fromMap(Map<String, dynamic>.from(result));
    if (value.text.isEmpty && value.paths.isEmpty) return null;
    return value;
  }

  Future<Map<String, dynamic>> deviceInfo() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getDeviceInfo',
    );
    return Map<String, dynamic>.from(result ?? {});
  }

  Future<bool> openApp(String package) async =>
      (await _channel.invokeMethod<bool>('openApp', {'package': package})) ??
      false;
  Future<bool> openUrl(String url) async =>
      (await _channel.invokeMethod<bool>('openUrl', {'url': url})) ?? false;
  Future<void> shareText(String text) =>
      _channel.invokeMethod('shareText', {'text': text});
  Future<bool> shareFile(String path) async =>
      (await _channel.invokeMethod<bool>('shareFile', {'path': path})) ?? false;
  void dispose() => _sharedController.close();
}

class SharedPayload {
  const SharedPayload({
    required this.text,
    required this.paths,
    required this.mime,
  });
  final String text;
  final List<String> paths;
  final String mime;
  factory SharedPayload.fromMap(Map<String, dynamic> map) => SharedPayload(
    text: (map['text'] as String?) ?? '',
    paths: ((map['paths'] as List?) ?? const []).cast<String>(),
    mime: (map['mime'] as String?) ?? '',
  );
}

class BiometricService {
  final LocalAuthentication auth = LocalAuthentication();
  Future<bool> authenticate() async {
    try {
      final available = await auth.isDeviceSupported();
      if (!available) return true;
      return auth.authenticate(localizedReason: 'Unlock CYSTEM');
    } catch (_) {
      return false;
    }
  }
}
