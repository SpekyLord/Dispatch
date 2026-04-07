import 'package:dispatch_mobile/core/i18n/app_locale.dart';
import 'package:dispatch_mobile/core/i18n/app_strings.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocaleActionButton extends ConsumerWidget {
  const LocaleActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    final strings = ref.watch(appStringsProvider);

    return PopupMenuButton<AppLocale>(
      icon: const Icon(Icons.translate, color: dc.onSurface),
      initialValue: locale,
      onSelected: (value) {
        ref.read(appLocaleProvider.notifier).state = value;
      },
      tooltip: strings.language,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: AppLocale.en,
          child: Text(strings.english),
        ),
        PopupMenuItem(
          value: AppLocale.fil,
          child: Text(strings.filipino),
        ),
      ],
    );
  }
}
