import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sohail_app/main.dart';
import 'package:sohail_app/src/messaging/messaging_service.dart';
import 'package:sohail_app/src/provisioning/provisioner.dart';
import 'package:sohail_app/src/provisioning/setup_controller.dart';
import 'package:sohail_app/src/settings.dart';
import 'package:sohail_app/src/ui/settings_screen.dart';
import 'package:sohail_app/src/ui/setup_screen.dart';

void main() {
  testWidgets('first launch asks for the message server', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(SohailApp(store: SettingsStore(), messaging: MessagingService()));
    await tester.pumpAndSettle();
    expect(find.text('Family: family'), findsOneWidget);
    expect(find.textContaining('Add your message server'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.text('Server address'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('This phone appears to the robots as app-'), 200,
        scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
    expect(find.textContaining('This phone appears to the robots as app-'), findsOneWidget);
  });

  testWidgets('setup screen: find robot, wrong code shows a message', (tester) async {
    const robot = FoundRobot(id: 'AA', name: 'PROV_SOHAIL_A1B2', rssi: -50);
    final c = SetupController(
      scanner: () => Stream.fromIterable([robot]),
      connector: (_) async => throw ProvisioningException("That code did not match. Check the 6 digits on the robot's screen."),
      ensurePermissions: () async => null,
    );
    await tester.pumpWidget(MaterialApp(home: SetupScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Sohail A1B2'), findsOneWidget);

    await tester.tap(find.text('Sohail A1B2'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code on Sohail A1B2'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), '111111');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('code did not match'), findsOneWidget);
  });
}
