import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'core/app_store.dart';
import 'ui/home.dart';

const navy = Color(0xFF082D50);
const gold = Color(0xFFB68A30);
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(await getApplicationSupportDirectory());
  await store.initialize();
  runApp(ReformedPiety(store: store));
}

class ReformedPiety extends StatelessWidget {
  final AppStore store;
  const ReformedPiety({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      ThemeData theme(Brightness brightness) {
        final dark = brightness == Brightness.dark;
        final scheme =
            ColorScheme.fromSeed(
              seedColor: navy,
              brightness: brightness,
            ).copyWith(
              primary: dark ? const Color(0xFFE1C376) : navy,
              secondary: gold,
            );
        return ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: dark
              ? const Color(0xFF121D28)
              : const Color(0xFFF7F5EF),
          appBarTheme: AppBarTheme(
            backgroundColor: dark
                ? const Color(0xFF121D28)
                : const Color(0xFFF7F5EF),
            foregroundColor: scheme.onSurface,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: dark ? const Color(0xFF1B2A38) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            indicatorColor: gold.withValues(alpha: .18),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        );
      }

      return MaterialApp(
        title: 'Reformed Piety',
        debugShowCheckedModeBanner: false,
        locale: Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: store.preferences.simplified ? 'Hans' : 'Hant',
        ),
        supportedLocales: const [
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: switch (store.preferences.theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: HomeScreen(store: store),
      );
    },
  );
}
