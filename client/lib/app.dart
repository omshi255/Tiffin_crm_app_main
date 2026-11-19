import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/locale/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'l10n/app_lang.dart';

/// Rebuilds the current screens when the language changes, without
/// disposing navigation or form state.
class _LocaleRebuild extends StatefulWidget {
  const _LocaleRebuild({required this.locale, required this.child});

  final Locale locale;
  final Widget child;

  @override
  State<_LocaleRebuild> createState() => _LocaleRebuildState();
}

class _LocaleRebuildState extends State<_LocaleRebuild> {
  @override
  void didUpdateWidget(_LocaleRebuild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locale == widget.locale) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void visit(Element element) {
        element.markNeedsBuild();
        element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TiffinCrmApp extends ConsumerWidget {
  const TiffinCrmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'TiffinCRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLang.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => _LocaleRebuild(
        locale: locale,
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: AppRouter.router,
    );
  }
}
