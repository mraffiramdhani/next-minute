import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notebook_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(NextMinuteApp(prefs: prefs));
}

class NextMinuteApp extends StatefulWidget {
  const NextMinuteApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<NextMinuteApp> createState() => _NextMinuteAppState();
}

class _NextMinuteAppState extends State<NextMinuteApp> {
  static const _themeKey = 'theme_mode';
  late ThemeMode _mode;

  @override
  void initState() {
    super.initState();
    final saved = widget.prefs.getString(_themeKey);
    _mode = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  void _toggleTheme(Brightness current) {
    setState(() {
      _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    });
    widget.prefs.setString(_themeKey, _mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Next Minute',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _mode,
      home: Builder(
        builder: (ctx) => NotebookPage(
          prefs: widget.prefs,
          onToggleTheme: () => _toggleTheme(Theme.of(ctx).brightness),
        ),
      ),
    );
  }
}
