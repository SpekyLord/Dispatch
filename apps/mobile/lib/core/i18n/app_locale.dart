import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLocale { en, fil }

final appLocaleProvider = StateProvider<AppLocale>((ref) => AppLocale.en);

