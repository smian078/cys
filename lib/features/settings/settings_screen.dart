import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../core/constants/model_constants.dart';
import '../../core/services/local_db.dart';
import '../../core/services/platform_bridge.dart';
import '../../core/services/secure_store.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SettingsBody(
        controller: ref.watch(settingsProvider),
      );
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody({required this.controller});
  final SettingsController controller;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  final nvidia = TextEditingController();
  final gemini = TextEditingController();
  final instructions = TextEditingController();
  final base = TextEditingController();
  bool showNvidia = false;
  bool showGemini = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    nvidia.text = await SecureStore.instance.readNvidia() ?? '';
    gemini.text = await SecureStore.instance.readGemini() ?? '';
    instructions.text = widget.controller.systemInstructions;
    base.text = widget.controller.nvidiaBaseUrl;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    nvidia.dispose();
    gemini.dispose();
    instructions.dispose();
    base.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('SYSTEM SETTINGS')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _section(context, 'PROVIDERS', [
            TextField(
              controller: nvidia,
              obscureText: !showNvidia,
              decoration: InputDecoration(
                labelText: 'NVIDIA API key',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => showNvidia = !showNvidia),
                  icon: Icon(showNvidia ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: base, decoration: const InputDecoration(labelText: 'NVIDIA base URL')),
            const SizedBox(height: 12),
            TextField(
              controller: gemini,
              obscureText: !showGemini,
              decoration: InputDecoration(
                labelText: 'Gemini API key',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => showGemini = !showGemini),
                  icon: Icon(showGemini ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Keys stay on this device in encrypted secure storage.', style: Theme.of(context).textTheme.bodySmall),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await SecureStore.instance.saveNvidia(nvidia.text);
                      await SecureStore.instance.saveGemini(gemini.text);
                      controller.updateNvidiaBaseUrl(
                        base.text.trim().isEmpty ? 'https://integrate.api.nvidia.com/v1' : base.text.trim(),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Provider settings saved locally.')));
                      }
                    },
                    child: const Text('SAVE PROVIDERS'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await SecureStore.instance.deleteNvidia();
                      await SecureStore.instance.deleteGemini();
                      if (mounted) setState(() {
                        nvidia.clear();
                        gemini.clear();
                      });
                    },
                    child: const Text('REMOVE KEYS'),
                  ),
                ),
              ],
            ),
          ]),
          _section(context, 'MODEL', [
            DropdownButtonFormField<String>(
              initialValue: controller.model,
              decoration: const InputDecoration(labelText: 'Main model'),
              items: const [
                DropdownMenuItem(value: ModelIds.nemotronSuper, child: Text('Nemotron 3 Super')),
                DropdownMenuItem(value: ModelIds.nemotronUltra, child: Text('Nemotron 3 Ultra')),
              ],
              onChanged: (value) {
                if (value != null) controller.updateModel(value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: controller.reasoningEffort,
              decoration: const InputDecoration(labelText: 'Reasoning effort'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (value) {
                if (value != null) controller.updateReasoning(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: 'Seed (optional)'),
              keyboardType: TextInputType.number,
              onChanged: (value) => controller.updateSeed(int.tryParse(value)),
            ),
          ]),
          _section(context, 'PERSONALIZATION', [
            TextField(
              controller: instructions,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Custom system instructions', alignLabelWithHint: true),
              onChanged: controller.updateSystemInstructions,
            ),
            SwitchListTile(
              value: controller.memoryEnabled,
              onChanged: controller.updateMemory,
              title: const Text('Use on-device memory in context'),
            ),
            SwitchListTile(
              value: controller.biometricLock,
              onChanged: (value) async {
                if (value) {
                  final ok = await BiometricService().authenticate();
                  if (!ok) return;
                }
                controller.updateBiometric(value);
              },
              title: const Text('Biometric app lock'),
            ),
          ]),
          const _MemorySection(),
          _section(context, 'APPEARANCE', [
            DropdownButtonFormField<ThemeMode>(
              initialValue: controller.themeMode,
              decoration: const InputDecoration(labelText: 'Theme'),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              ],
              onChanged: (value) {
                if (value != null) controller.updateTheme(value);
              },
            ),
            const SizedBox(height: 12),
            _AccentPicker(value: controller.accent, onChanged: controller.updateAccent),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: children))),
        ],
      ),
    );
  }
}

class _MemorySection extends StatefulWidget {
  const _MemorySection();

  @override
  State<_MemorySection> createState() => _MemorySectionState();
}

class _MemorySectionState extends State<_MemorySection> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await LocalDb.instance.memories();
    if (mounted) setState(() => rows = data);
  }

  Future<void> _edit(Map<String, Object?> row) async {
    final key = TextEditingController(text: row['key'] as String);
    final value = TextEditingController(text: row['value'] as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: key, decoration: const InputDecoration(labelText: 'Fact / preference')),
            TextField(controller: value, decoration: const InputDecoration(labelText: 'Value')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    final keyText = key.text.trim();
    final valueText = value.text.trim();
    key.dispose();
    value.dispose();
    if (ok == true && keyText.isNotEmpty) {
      await LocalDb.instance.upsertMemory(
        row['id'] as String,
        keyText,
        valueText,
        (row['enabled'] as int? ?? 0) == 1,
      );
      await _load();
    }
  }

  Future<void> _add() async {
    final key = TextEditingController();
    final value = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: key, decoration: const InputDecoration(labelText: 'Fact / preference')),
            TextField(controller: value, decoration: const InputDecoration(labelText: 'Value')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    final keyText = key.text.trim();
    final valueText = value.text.trim();
    key.dispose();
    value.dispose();
    if (ok == true && keyText.isNotEmpty) {
      await LocalDb.instance.upsertMemory(const Uuid().v4(), keyText, valueText, true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MEMORY', style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                for (final row in rows)
                  ListTile(
                    onTap: () => _edit(row),
                    title: Text(row['key'] as String),
                    subtitle: Text(row['value'] as String),
                    leading: Switch(
                      value: (row['enabled'] as int? ?? 0) == 1,
                      onChanged: (value) async {
                        await LocalDb.instance.upsertMemory(row['id'] as String, row['key'] as String, row['value'] as String, value);
                        await _load();
                      },
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete memory',
                      onPressed: () async {
                        await LocalDb.instance.deleteMemory(row['id'] as String);
                        await _load();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ListTile(leading: const Icon(Icons.add), title: const Text('Add memory'), onTap: _add),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.value, required this.onChanged});
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF7C5CFF),
      Color(0xFF00C2FF),
      Color(0xFF00D68F),
      Color(0xFFFF4D8D),
      Color(0xFFFFB020),
      Color(0xFF8DFF5B),
    ];
    return Wrap(
      spacing: 10,
      children: colors
          .map(
            (color) => GestureDetector(
              onTap: () => onChanged(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: value.value == color.value ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
