import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_watch/src/monitor.dart';
import 'package:wifi_watch/src/router/demo_source.dart';
import 'package:wifi_watch/src/settings.dart';
import 'package:wifi_watch/src/ui/home_screen.dart';

void main() {
  testWidgets('demo network: devices, usage and a new device', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 10, 24, 12);
    final demo = DemoSource(rng: Random(7), now: () => now);
    final monitor = Monitor(makeSource: (_) => demo);
    const settings = AppSettings(pollSeconds: 60);

    await tester.runAsync(() => monitor.start(settings));
    for (var i = 0; i < 6; i++) {
      now = now.add(const Duration(seconds: 10));
      await tester.runAsync(monitor.poll);
    }
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(monitor: monitor, settings: settings, onSettingsChanged: (_) async {}),
    ));

    expect(find.text('WiFi Watch'), findsOneWidget);
    expect(find.text('Living-Room-TV'), findsOneWidget);
    expect(find.textContaining('New device joined your Wi-Fi: Galaxy-A15'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.textContaining('New device joined'), findsNothing);

    await tester.tap(find.text('Usage'));
    await tester.pumpAndSettle();
    expect(find.text('Top devices'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Living-Room-TV'), 200);
    expect(find.textContaining('Living-Room-TV'), findsWidgets);

    await tester.runAsync(monitor.stop);
  });
}
