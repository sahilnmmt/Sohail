import 'package:flutter/material.dart';

import 'src/monitor.dart';
import 'src/settings.dart';
import 'src/ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WifiWatchApp(store: SettingsStore(), monitor: Monitor()));
}

class WifiWatchApp extends StatefulWidget {
  final SettingsStore store;
  final Monitor monitor;
  const WifiWatchApp({super.key, required this.store, required this.monitor});

  @override
  State<WifiWatchApp> createState() => _WifiWatchAppState();
}

class _WifiWatchAppState extends State<WifiWatchApp> with WidgetsBindingObserver {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.monitor.onVariantFound = (v, user) {
      final s = _settings?.copyWith(variant: () => v, username: user);
      if (s == null) return;
      setState(() => _settings = s);
      widget.store.save(s);
    };
    widget.store.load().then((s) {
      if (!mounted) return;
      setState(() => _settings = s);
      widget.monitor.start(s);
    });
  }

  // Polling only runs while the app is on screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_settings == null) return;
    if (state == AppLifecycleState.resumed) {
      widget.monitor.resume();
    } else if (state == AppLifecycleState.paused) {
      widget.monitor.stop();
    }
  }

  Future<void> _save(AppSettings s) async {
    await widget.store.save(s);
    setState(() => _settings = s);
    await widget.monitor.start(s);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E88A8);
    return MaterialApp(
      title: 'WiFi Watch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: _settings == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomeScreen(monitor: widget.monitor, settings: _settings!, onSettingsChanged: _save),
    );
  }
}
