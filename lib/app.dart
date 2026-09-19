import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'features/chat/chat_screen.dart';
import 'features/shell/system_drawer.dart';
import 'features/shell/boot_overlay.dart';
import 'core/services/platform_bridge.dart';

class CystemApp extends ConsumerWidget {
  const CystemApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CYSTEM',
      theme: AppTheme.light(settings.accent),
      darkTheme: AppTheme.dark(settings.accent),
      themeMode: settings.themeMode,
      home: const CystemShell(),
    );
  }
}

class CystemShell extends ConsumerStatefulWidget {
  const CystemShell({super.key});

  @override
  ConsumerState<CystemShell> createState() => _CystemShellState();
}

class _CystemShellState extends ConsumerState<CystemShell>
    with WidgetsBindingObserver {
  bool locked = false;
  bool booting = true;
  final rootScaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => booting = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = ref.read(settingsProvider).biometricLock;
    if (state == AppLifecycleState.paused && enabled)
      setState(() => locked = true);
    if (state == AppLifecycleState.resumed && locked && enabled) _unlock();
  }

  Future<void> _unlock() async {
    final ok = await ref.read(platformServiceProvider).authenticate();
    if (mounted && ok) setState(() => locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          key: rootScaffoldKey,
          extendBodyBehindAppBar: true,
          body: ChatScreen(hostScaffoldKey: rootScaffoldKey),
          drawer: const SystemDrawer(),
        ),
        if (booting) const Positioned.fill(child: BootOverlay()),
        if (locked) Positioned.fill(child: _LockScreen(onUnlock: _unlock)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Center(
        child: FilledButton.icon(
          onPressed: onUnlock,
          icon: const Icon(Icons.fingerprint),
          label: const Text('UNLOCK CYSTEM'),
        ),
      ),
    ),
  );
}

final settingsProvider = ChangeNotifierProvider<SettingsController>(
  (ref) => SettingsController(),
);
final currentChatIdProvider = StateProvider<String?>((ref) => null);
final platformServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

class SettingsController extends ChangeNotifier {
  SettingsController() {
    _load();
  }
  ThemeMode themeMode = ThemeMode.dark;
  Color accent = const Color(0xFF7C5CFF);
  bool biometricLock = false;
  bool memoryEnabled = true;
  String systemInstructions = '';
  String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  String model = 'nvidia/nemotron-3-super-120b-a12b';
  String reasoningEffort = 'low';
  int? seed;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.dark.index];
    accent = Color(p.getInt('accent') ?? accent.value);
    biometricLock = p.getBool('biometricLock') ?? false;
    memoryEnabled = p.getBool('memoryEnabled') ?? true;
    systemInstructions = p.getString('systemInstructions') ?? '';
    nvidiaBaseUrl = p.getString('nvidiaBaseUrl') ?? nvidiaBaseUrl;
    model = p.getString('model') ?? model;
    reasoningEffort = p.getString('reasoningEffort') ?? reasoningEffort;
    seed = p.getInt('seed');
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', themeMode.index);
    await p.setInt('accent', accent.value);
    await p.setBool('biometricLock', biometricLock);
    await p.setBool('memoryEnabled', memoryEnabled);
    await p.setString('systemInstructions', systemInstructions);
    await p.setString('nvidiaBaseUrl', nvidiaBaseUrl);
    await p.setString('model', model);
    await p.setString('reasoningEffort', reasoningEffort);
    if (seed == null)
      await p.remove('seed');
    else
      await p.setInt('seed', seed!);
  }

  void updateTheme(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    _save();
  }

  void updateAccent(Color value) {
    accent = value;
    notifyListeners();
    _save();
  }

  void updateSystemInstructions(String value) {
    systemInstructions = value;
    notifyListeners();
    _save();
  }

  void updateMemory(bool value) {
    memoryEnabled = value;
    notifyListeners();
    _save();
  }

  void updateBiometric(bool value) {
    biometricLock = value;
    notifyListeners();
    _save();
  }

  void updateModel(String value) {
    model = value;
    notifyListeners();
    _save();
  }

  void updateReasoning(String value) {
    reasoningEffort = value;
    notifyListeners();
    _save();
  }

  void updateSeed(int? value) {
    seed = value;
    notifyListeners();
    _save();
  }

  void updateNvidiaBaseUrl(String value) {
    nvidiaBaseUrl = value;
    notifyListeners();
    _save();
  }
}
