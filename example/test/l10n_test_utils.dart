import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Mirrors lib/main.dart's localization setup; pass locale to pin a
/// language in widget tests (production follows the system locale).
Widget localizedTestApp(Widget child, {Locale? locale}) {
  return MaterialApp(
    locale: locale,
    onGenerateTitle: (BuildContext context) =>
        AppLocalizations.of(context).appTitle,
    localizationsDelegates: <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    // No real fonts in tests: shrink text scaling so long English strings
    // do not cause false overflow errors in the 220-wide panels.
    builder: (BuildContext context, Widget? home) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(0.6)),
      child: home!,
    ),
    home: Scaffold(body: child),
  );
}

AppLocalizations l10nFor(Locale locale) => lookupAppLocalizations(locale);
