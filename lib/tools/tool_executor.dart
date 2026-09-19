import 'dart:convert';
import 'tool_registry.dart';

class ToolExecutor {
  ToolExecutor(this.registry);
  final ToolRegistry registry;

  Future<String> execute(String name, String argumentsJson) async {
    try {
      if (name == 'cystem_tools') {
        final wrapper = jsonDecode(argumentsJson);
        if (wrapper is Map &&
            wrapper['tool'] is String &&
            wrapper['arguments'] is Map) {
          return await execute(
            wrapper['tool'] as String,
            jsonEncode(wrapper['arguments']),
          );
        }
      }
      final args = registry.validateInvocation(name, argumentsJson);
      final result = await registry.byName(name)!.execute(args);
      return jsonEncode({'ok': true, 'result': result});
    } catch (error) {
      return jsonEncode({'ok': false, 'error': error.toString()});
    }
  }
}
