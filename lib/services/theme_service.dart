import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide light/dark mode, toggled from MapScreen's menu and persisted
/// across restarts. Just a single global ValueNotifier rather than pulling
/// in a state management package, since this is the only piece of
/// cross-screen UI state the app needs. Deliberately only ever light or
/// dark (never ThemeMode.system) - a plain on/off toggle rather than a
/// three-way picker, seeded from the device's own setting on first launch
/// so it still feels reasonable out of the box.
class ThemeService {
  ThemeService._();
  static final instance = ThemeService._();

  static const _prefsKey = 'themeMode';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else if (saved == 'light') {
      themeMode.value = ThemeMode.light;
    } else {
      final platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      themeMode.value =
          platformBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    }
  }

  Future<void> toggle() async {
    final next = themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    themeMode.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next == ThemeMode.dark ? 'dark' : 'light');
  }
}
