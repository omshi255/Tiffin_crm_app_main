import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_lang.dart';

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => AppLang.locale;

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode != 'en' && locale.languageCode != 'hi') return;
    await AppLang.persist(locale);
    state = locale;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
