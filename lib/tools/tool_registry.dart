import 'dart:convert';

class ToolValidationException implements Exception {
  const ToolValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class CystemTool {
  String get name;
  String get description;
  Map<String, dynamic> get schema;
  Future<Map<String, dynamic>> execute(Map<String, dynamic> arguments);
}

class ToolRegistry {
  final Map<String, CystemTool> _tools = {};
  void register(CystemTool tool) => _tools[tool.name] = tool;
  Iterable<CystemTool> get all => _tools.values;
  CystemTool? byName(String name) => _tools[name];

  List<Map<String, dynamic>> openAiDefinitions() => _tools.values
      .map(
        (tool) => {
          'type': 'function',
          'function': {
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.schema,
          },
        },
      )
      .toList();

  Map<String, dynamic> validateInvocation(String name, String rawArguments) {
    final tool = byName(name);
    if (tool == null) throw const ToolValidationException('Unknown tool');
    dynamic decoded;
    try {
      decoded = jsonDecode(rawArguments);
    } catch (_) {
      throw const ToolValidationException('Arguments must be valid JSON');
    }
    if (decoded is! Map<String, dynamic>)
      throw const ToolValidationException(
        'Tool arguments must be a JSON object',
      );
    _validateSchema(tool.schema, decoded);
    return decoded;
  }

  void _validateSchema(Map<String, dynamic> schema, Map<String, dynamic> data) {
    final required = (schema['required'] as List?)?.cast<String>() ?? const [];
    for (final key in required)
      if (!data.containsKey(key))
        throw ToolValidationException('Missing required argument: $key');
    final properties =
        (schema['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final entry in data.entries) {
      if (!properties.containsKey(entry.key))
        throw ToolValidationException('Unexpected argument: ${entry.key}');
      final type = (properties[entry.key] as Map?)?['type'];
      if (type == 'string' && entry.value is! String)
        throw ToolValidationException('${entry.key} must be a string');
      if (type == 'boolean' && entry.value is! bool)
        throw ToolValidationException('${entry.key} must be a boolean');
      if (type == 'integer' && entry.value is! int)
        throw ToolValidationException('${entry.key} must be an integer');
    }
  }
}
