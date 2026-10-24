import 'package:flutter/material.dart';

import 'src/messaging/messaging_service.dart';
import 'src/settings.dart';
import 'src/ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SohailApp(store: SettingsStore(), messaging: MessagingService()));
}

class SohailApp extends StatefulWidget {
  final SettingsStore store;
  final MessagingService messaging;
  const SohailApp({super.key, required this.store, required this.messaging});

  @override
  State<SohailApp> createState() => _SohailAppState();
}

class _SohailAppState extends State<SohailApp> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((s) {
      if (!mounted) return;
      setState(() => _settings = s);
      widget.messaging.connect(s);
    });
  }

  Future<void> _save(AppSettings s) async {
    await widget.store.save(s);
    setState(() => _settings = s);
    await widget.messaging.connect(s);
  }

  @override
  void dispose() {
    widget.messaging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0A8FB0); // the robot's eye colour
    return MaterialApp(
      title: 'Sohail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: _settings == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomeScreen(settings: _settings!, messaging: widget.messaging, onSettingsChanged: _save),
    );
  }
}
