/// Composición de la aplicación WATAP Mobile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants.dart';
import 'data/local/app_database.dart';
import 'data/local/steam_token_store.dart';
import 'data/repositories/activity_repository.dart';
import 'data/repositories/preferences_repository.dart';
import 'data/repositories/profiles_repository.dart';
import 'data/steam/family_groups_client.dart';
import 'data/steam/steam_api_client.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'services/family_group_sync.dart';
import 'services/refresh_coordinator.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/error_state.dart';
import 'widgets/loading_state.dart';

/// Arranque de la aplicación.
///
/// Abre el almacenamiento local y construye el controlador antes de mostrar la
/// interfaz. Si algo falla, se muestra un error recuperable en lugar de
/// cerrarse.
class WatapBootstrap extends StatefulWidget {
  const WatapBootstrap({super.key, this.overrides});

  /// Permite inyectar dependencias alternativas en las pruebas.
  final AppController Function()? overrides;

  @override
  State<WatapBootstrap> createState() => _WatapBootstrapState();
}

class _WatapBootstrapState extends State<WatapBootstrap> {
  AppController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AppController controller = widget.overrides != null
          ? widget.overrides!()
          : await createAppController();
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo preparar WATAP Mobile: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController? controller = _controller;

    if (_loading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: LoadingState(message: 'Preparando WATAP Mobile…'),
        ),
      );
    }

    if (controller == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ErrorState(
            title: 'No se pudo iniciar WATAP',
            message: _error ?? 'Error desconocido durante el arranque.',
            onRetry: _bootstrap,
          ),
        ),
      );
    }

    return WatapApp(controller: controller);
  }
}

/// Aplicación principal, con el controlador ya inicializado.
class WatapApp extends StatelessWidget {
  const WatapApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        locale: const Locale('es'),
        supportedLocales: const <Locale>[Locale('es'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (BuildContext context, Widget? child) {
          // Se respeta el tamaño de fuente del sistema sin desbordar.
          final MediaQueryData media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.6,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const DashboardScreen(),
      ),
    );
  }
}

/// Construye el controlador con las dependencias reales.
Future<AppController> createAppController() async {
  final AppDatabase database = await AppDatabase.open();
  final SteamTokenStore tokenStore = SecureSteamTokenStore();
  final SteamApiClient apiClient = SteamApiClient();
  final FamilyGroupsClient familyGroupsClient = FamilyGroupsClient();

  final ProfilesRepository profilesRepository = ProfilesRepository(database);
  final ActivityRepository activityRepository = ActivityRepository(database);
  final PreferencesRepository preferencesRepository =
      PreferencesRepository(database);

  final FamilyGroupSyncService familySyncService = FamilyGroupSyncService(
    groups: familyGroupsClient,
    api: apiClient,
    profiles: profilesRepository,
  );

  final RefreshCoordinator refreshCoordinator = RefreshCoordinator(
    api: apiClient,
    activities: activityRepository,
    profiles: profilesRepository,
  );

  return AppController(
    database: database,
    profilesRepository: profilesRepository,
    activityRepository: activityRepository,
    preferencesRepository: preferencesRepository,
    tokenStore: tokenStore,
    apiClient: apiClient,
    familyGroupsClient: familyGroupsClient,
    familySyncService: familySyncService,
    refreshCoordinator: refreshCoordinator,
  );
}
