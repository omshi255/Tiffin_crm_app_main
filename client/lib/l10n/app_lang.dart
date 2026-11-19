import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'en.dart';
import 'hi.dart';

/// Central lookup for English and Hindi UI copy.
/// Screens call [tr] instead of writing a translation inside the widget.
class AppLang {
  AppLang._();

  static const storageKey = 'app_locale';
  static const supported = [Locale('en'), Locale('hi')];

  static Locale locale = const Locale('en');

  static const Map<String, Map<String, String>> _tables = {
    'en': en,
    'hi': hi,
  };

  static Future<void> load(SharedPreferences prefs) async {
    final code = prefs.getString(storageKey);
    if (code == 'hi' || code == 'en') {
      locale = Locale(code!);
    } else {
      locale = const Locale('en');
    }
  }

  static Future<void> persist(Locale value) async {
    locale = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, value.languageCode);
  }

  static String t(String key) {
    final lang = locale.languageCode;
    return _tables[lang]?[key] ?? en[key] ?? key;
  }

  /// Replaces `{name}` placeholders in a translation.
  static String format(String key, Map<String, String> args) {
    var value = t(key);
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }
}

String tr(String key) => AppLang.t(key);

String trf(String key, Map<String, String> args) => AppLang.format(key, args);
