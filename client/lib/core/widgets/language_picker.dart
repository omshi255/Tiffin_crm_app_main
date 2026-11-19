import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../locale/locale_provider.dart';
import '../theme/app_colors.dart';
import '../../l10n/app_lang.dart';

/// Settings row that opens the English / Hindi picker.
class LanguagePickerTile extends ConsumerWidget {
  const LanguagePickerTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1B1F2E) : Colors.white;
    final border = isDark ? const Color(0xFF2F3347) : const Color(0xFFE2E8F0);
    final ink = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;
    final muted = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;
    final current = code == 'hi' ? tr('hindi') : tr('english');

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        showLanguagePicker(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF241B42) : const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.translate_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('language'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('languageSubtitle'),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            Text(
              current,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

Future<void> showLanguagePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(localeProvider).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1B1F2E) : Colors.white;
    final ink = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3F3A5C) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('language'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('languageSubtitle'),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _option(context, ref, code: 'en', label: tr('english'), selected: selected == 'en'),
          const SizedBox(height: 8),
          _option(context, ref, code: 'hi', label: tr('hindi'), selected: selected == 'hi'),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    WidgetRef ref, {
    required String code,
    required String label,
    required bool selected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        await ref.read(localeProvider.notifier).setLocale(Locale(code));
        if (context.mounted) Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? const Color(0xFF2F3347) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
