import '../core/services/platform_bridge.dart';
import 'tool_registry.dart';

class PhoneDeviceInfoTool implements CystemTool {
  PhoneDeviceInfoTool(this.bridge);
  final AndroidBridge bridge;
  @override
  String get name => 'phone_device_info';
  @override
  String get description =>
      'Read non-sensitive Android device information such as model, Android version and CPU ABIs.';
  @override
  Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': <String, dynamic>{},
    'required': <String>[],
  };
  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) =>
      bridge.deviceInfo();
}

class OpenPhoneAppTool implements CystemTool {
  OpenPhoneAppTool(this.bridge);
  final AndroidBridge bridge;
  @override
  String get name => 'open_phone_app';
  @override
  String get description =>
      'Open a supported installed Android app by package name.';
  @override
  Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': {
      'package': {'type': 'string'},
    },
    'required': ['package'],
  };
  @override
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments) async {
    final package = arguments['package'] as String;
    const allow = {
      'com.android.settings',
      'com.google.android.dialer',
      'com.google.android.apps.messaging',
    };
    if (!allow.contains(package)) {
      return {
        'ok': false,
        'error': 'Package is not in the supported allowlist.',
      };
    }
    final opened = await bridge.openApp(package);
    return {'ok': opened};
  }
}
