import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _goFullScreen();
  runApp(const LudoApp());
}

/// Hides the status and navigation bars. A swipe from the edge shows them
/// briefly; they hide again on their own.
void _goFullScreen() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});

  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _goFullScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: const SetupScreen(),
    );
  }
}
