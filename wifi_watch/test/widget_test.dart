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

    // Joined after the first look, so it is unknown until you say it's yours.
    await tester.tap(find.text('Unknown 1'));
    await tester.pump();
    expect(find.text('Galaxy-A15'), findsOneWidget);
    expect(find.text('Living-Room-TV'), findsNothing);

    await tester.tap(find.text("IT'S OURS"));
    await tester.pump();
    expect(find.textContaining('New device joined'), findsNothing);
    expect(find.text('Unknown 0'), findsOneWidget);

    await tester.tap(find.textContaining('All '));
    await tester.enterText(find.byType(TextField), 'tv');
    await tester.pump();
    expect(find.text('Living-Room-TV'), findsOneWidget);
    expect(find.text('Laptop'), findsNothing);

    await tester.tap(find.text('Living-Room-TV'));
    await tester.pumpAndSettle();
    expect(find.text('TV / streaming'), findsOneWidget);
    expect(find.text('I know this device'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Recent visits'), 200);
    expect(find.text('Time online, last 7 days'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usage'));
    await tester.pumpAndSettle();
    expect(find.text('Top devices'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Living-Room-TV'), 200);
    expect(find.textContaining('Living-Room-TV'), findsWidgets);

    await tester.runAsync(monitor.stop);
  });
}
