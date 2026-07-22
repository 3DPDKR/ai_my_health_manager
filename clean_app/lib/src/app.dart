import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'health_home.dart';

class HealthAssistantApp extends StatefulWidget {
  const HealthAssistantApp({super.key});

  @override
  State<HealthAssistantApp> createState() => _HealthAssistantAppState();
}

class _HealthAssistantAppState extends State<HealthAssistantApp> {
  String _language = 'system';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _language = prefs.getString('language') ?? 'system');
  }

  Locale? get _locale => switch (_language) {
        'ko' => const Locale('ko'),
        'en' => const Locale('en'),
        'ja' => const Locale('ja'),
        'zh' => const Locale('zh'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 건강비서',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('ko'),
        Locale('en'),
        Locale('ja'),
        Locale('zh'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176F46)),
        scaffoldBackgroundColor: const Color(0xFFF5F8F4),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
      ),
      home: HealthHome(
        initialLanguage: _language,
        onLanguageChanged: (value) => setState(() => _language = value),
      ),
    );
  }
}
