import '../core/services/local_db.dart';
import '../core/services/platform_bridge.dart';
import '../services/attachment_service.dart';
import '../services/pipeline_coordinator.dart';
import '../tools/phone_tools.dart';
import '../tools/tool_executor.dart';
import '../tools/tool_registry.dart';

class CystemServices {
  CystemServices._();
  static final instance = CystemServices._();

  late final AttachmentService attachmentService = AttachmentService(
    LocalDb.instance,
  );
  late final AndroidBridge android = AndroidBridge();
  late final ToolRegistry registry = ToolRegistry()
    ..register(PhoneDeviceInfoTool(android))
    ..register(OpenPhoneAppTool(android));
  late final ToolExecutor toolExecutor = ToolExecutor(registry);
  late final PipelineCoordinator pipeline = PipelineCoordinator(
    attachments: attachmentService,
    tools: toolExecutor,
  );
}
