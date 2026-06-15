import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'nav/main_scaffold.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load the CMS-injected config (assets/config/app_config.json).
  final config = await AppConfig.load();

  // 2. Single shared API client (baseUrl + active language come from config).
  final api = ApiClient.fromConfig(config);

  runApp(CmsApp(config: config, api: api));
}

/// Root widget. Holds the active locale in state so a language switch rebuilds
/// the whole app (theme + Directionality + the `lang` sent to the API).
class CmsApp extends StatefulWidget {
  const CmsApp({super.key, required this.config, required this.api});

  final AppConfig config;
  final ApiClient api;

  @override
  State<CmsApp> createState() => _CmsAppState();
}

class _CmsAppState extends State<CmsApp> {
  late String _lang = widget.config.languages.defaultLang;

  void _setLanguage(String lang) {
    if (lang == _lang) return;
    if (!widget.config.languages.supported.contains(lang)) return;
    setState(() {
      _lang = lang;
      widget.api.language = lang;
    });
  }

  @override
  void dispose() {
    widget.api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme(widget.config.branding);
    final isRtl = widget.config.languages.isRtl(_lang);

    return AppScope(
      config: widget.config,
      api: widget.api,
      lang: _lang,
      setLanguage: _setLanguage,
      child: MaterialApp(
        title: widget.config.titleFor(_lang),
        debugShowCheckedModeBanner: false,
        theme: theme.light,
        darkTheme: theme.dark,
        themeMode: theme.themeMode,
        locale: Locale(_lang),
        supportedLocales:
            widget.config.languages.supported.map((l) => Locale(l)),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Force text direction from the config's `rtl` list, independent of
        // whether GlobalWidgetsLocalizations knows the locale.
        builder: (context, child) => Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        ),
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: const MainScaffold(),
      ),
    );
  }
}

/// App-wide access to the parsed config, the API client, the active language
/// and a language setter. Screens read it via `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.config,
    required this.api,
    required this.lang,
    required this.setLanguage,
    required super.child,
  });

  final AppConfig config;
  final ApiClient api;
  final String lang;
  final void Function(String lang) setLanguage;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      lang != old.lang || api != old.api || config != old.config;
}
