import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cystem/core/theme/app_theme.dart';
import 'package:cystem/features/shell/boot_overlay.dart';

void main() {
  testWidgets('boot overlay renders with application theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(const Color(0xFF7C5CFF)),
        home: const BootOverlay(),
      ),
    );
    expect(find.byType(BootOverlay), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
