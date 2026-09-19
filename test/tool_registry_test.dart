import 'package:flutter_test/flutter_test.dart';
import 'package:cystem/tools/tool_registry.dart';

class DemoTool implements CystemTool {
  @override String get name => 'demo';
  @override String get description => 'demo';
  @override Map<String, dynamic> get schema => {'type':'object','properties':{'message':{'type':'string'}},'required':['message']};
  @override Future<Map<String,dynamic>> execute(Map<String,dynamic> arguments) async => {'echo':arguments['message']};
}

void main(){
  test('validates and accepts typed arguments',(){final r=ToolRegistry()..register(DemoTool());expect(r.validateInvocation('demo','{"message":"hello"}')['message'],'hello');});
  test('rejects missing required args',(){final r=ToolRegistry()..register(DemoTool());expect(()=>r.validateInvocation('demo','{}'),throwsA(isA<ToolValidationException>()));});
  test('rejects malformed json',(){final r=ToolRegistry()..register(DemoTool());expect(()=>r.validateInvocation('demo','{oops'),throwsA(isA<ToolValidationException>()));});
}
