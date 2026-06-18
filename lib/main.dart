import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/services/runtime_bootstrap.dart';
import 'nav/main_scaffold.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

/// The root Navigator key. Lets the Phase-6f services (deep links, push taps)
/// navigate from outside the widget tree, and lets the analytics observer track
/// route changes. A single shared key.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load the CMS-injected config (assets/config/app_config.json). FIRST, so
  //    everything below (theme, baseUrl, runtime context) is config-driven.
  final config = await AppConfig.load();

  // 2. Single shared API client (baseUrl + active language come from config).
  final api = ApiClient.fromConfig(config);

  // A shared notifier for the active language, so the (widget-free) runtime
  // services can read the current locale via a callback without depending on
  // the widget tree. Updated by [_CmsAppState._setLanguage].
  final langHolder = ValueNotifier<String>(config.languages.defaultLang);

  // 3. Phase-6f runtime composition root. Wires runtime config, device/push,
  //    deep links, offline sync, analytics + secure session — and runs the
  //    ordered bootstrap (config → flags/theme → device → push → deep links →
  //    sync + analytics). Every step is guarded, so a missing capability
  //    (no network / no Firebase / no biometrics) never blocks startup.
  final bootstrap = RuntimeBootstrap(
    api: api,
    config: config,
    localeProvider: () => langHolder.value,
    // Navigate via the root Navigator's named routes (the same the menu uses);
    // resolved by AppRouter.onGenerateRoute. No-op until the Navigator exists.
    navigate: (route) {
      final nav = rootNavigatorKey.currentState;
      if (nav != null && route.isNotEmpty) nav.pushNamed(route);
    },
  );

  // Fire-and-forget the bootstrap: the UI paints immediately (baked config),
  // and flags/theme/etc. light up as the envelope + services resolve. We do NOT
  // await it so a slow/absent network never delays first paint.
  // ignore: discarded_futures
  bootstrap.start();

  runApp(CmsApp(config: config, api: api, bootstrap: bootstrap, langHolder: langHolder));
}

/// Root widget. Holds the active locale in state so a language switch rebuilds
/// the whole app (theme + Directionality + the `lang` sent to the API), and
/// rebuilds the theme when the runtime config envelope changes (remote theme
/// switching).
class CmsApp extends StatefulWidget {
  const CmsApp({
    super.key,
    required this.config,
    required this.api,
    required this.bootstrap,
    required this.langHolder,
  });

  final AppConfig config;
  final ApiClient api;
  final RuntimeBootstrap bootstrap;
  final ValueNotifier<String> langHolder;

  @override
  State<CmsApp> createState() => _CmsAppState();
}

class _CmsAppState extends State<CmsApp> {
  late String _lang = widget.config.languages.defaultLang;

  @override
  void initState() {
    super.initState();
    // Rebuild when the runtime envelope changes (e.g. remote theme switch).
    widget.bootstrap.runtime.configNotifier.addListener(_onRuntimeChanged);
    // Let the bootstrap ask us to re-apply the theme after a resume refresh.
    widget.bootstrap.onConfigChanged = _onRuntimeChanged;
  }

  void _onRuntimeChanged() {
    if (mounted) setState(() {});
  }

  void _setLanguage(String lang) {
    if (lang == _lang) return;
    if (!widget.config.languages.supported.contains(lang)) return;
    setState(() {
      _lang = lang;
      widget.api.language = lang;
      widget.langHolder.value = lang;
    });
    // Re-fetch the runtime envelope + heartbeat for the new language.
    // ignore: discarded_futures
    widget.bootstrap.onLocaleChanged();
  }

  @override
  void dispose() {
    widget.bootstrap.runtime.configNotifier.removeListener(_onRuntimeChanged);
    widget.bootstrap.dispose();
    widget.api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 4c/6f: build the theme from the baked Design System tokens, with the
    // runtime envelope's theme.mode applied on top (remote theme switching).
    final theme = AppTheme.fromConfigWithRuntime(
      widget.config,
      widget.bootstrap.runtime.theme,
    );
    final isRtl = widget.config.languages.isRtl(_lang);

    return AppScope(
      config: widget.config,
      api: widget.api,
      bootstrap: widget.bootstrap,
      lang: _lang,
      setLanguage: _setLanguage,
      child: MaterialApp(
        title: widget.config.titleFor(_lang),
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
        // Phase 6f: emit screen_view analytics for every route change.
        navigatorObservers: [widget.bootstrap.navigatorObserver],
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

/// App-wide access to the parsed config, the API client, the active language,
/// a language setter, and (Phase 6f) the runtime services. Screens read it via
/// `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.config,
    required this.api,
    required this.bootstrap,
    required this.lang,
    required this.setLanguage,
    required super.child,
  });

  final AppConfig config;
  final ApiClient api;

  /// Phase 6f — the runtime services (runtime config, sync, analytics, …).
  /// Screens can read flags (`bootstrap.runtime.flagBool(...)`), favorite
  /// toggles (`bootstrap.sync.toggleFavorite(...)`), and emit analytics.
  final RuntimeBootstrap bootstrap;

  final String lang;
  final void Function(String lang) setLanguage;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      lang != old.lang ||
      api != old.api ||
      config != old.config ||
      bootstrap != old.bootstrap;
}
