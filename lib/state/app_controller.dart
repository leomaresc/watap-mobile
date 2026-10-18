/// Estado de la aplicación.
///
/// Se usa `ChangeNotifier` del SDK (sin dependencias adicionales de gestión de
/// estado) expuesto mediante un `InheritedNotifier`. Toda la lógica de negocio
/// vive en los servicios y repositorios; este controlador solo los coordina y
/// mantiene el estado observable por la interfaz.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/constants.dart';
import '../core/models.dart';
import '../core/validators.dart';
import '../data/local/app_database.dart';
import '../data/local/image_cache_service.dart';
import '../data/local/secure_api_key_store.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/profiles_repository.dart';
import '../data/steam/steam_api_client.dart';
import '../data/steam/steam_api_errors.dart';
import '../services/activity_aggregator.dart';
import '../services/demo_data.dart';
import '../services/refresh_coordinator.dart';

/// Secciones de la navegación inferior.
enum AppSection {
  /// Juegos recientes agrupados por integrante.
  recent,

  /// Actividad agregada de todos los integrantes.
  overview,

  /// Administración de perfiles.
  members,

  /// Clave de API, preferencias, caché y privacidad.
  settings;

  static AppSection fromName(String? name) {
    for (final AppSection s in AppSection.values) {
      if (s.name == name) return s;
    }
    return AppSection.recent;
  }

  String get labelEs => switch (this) {
        AppSection.recent => 'Recientes',
        AppSection.overview => 'General',
        AppSection.members => 'Integrantes',
        AppSection.settings => 'Ajustes',
      };
}

/// Resultado de una operación solicitada desde la interfaz.
class OperationResult {
  const OperationResult({
    required this.success,
    required this.messageEs,
    this.steamId64,
  });

  const OperationResult.ok(this.messageEs, {this.steamId64}) : success = true;

  const OperationResult.error(this.messageEs)
      : success = false,
        steamId64 = null;

  final bool success;
  final String messageEs;
  final String? steamId64;
}

/// Resultado de intentar cargar la lista de amigos.
class FriendImportResult {
  const FriendImportResult({
    required this.friends,
    required this.messageEs,
    required this.isError,
  });

  final List<SteamPlayerSummary> friends;
  final String messageEs;
  final bool isError;

  bool get isEmpty => friends.isEmpty && !isError;
}

/// Controlador principal de WATAP Mobile.
class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required ProfilesRepository profilesRepository,
    required ActivityRepository activityRepository,
    required PreferencesRepository preferencesRepository,
    required ApiKeyStore apiKeyStore,
    required SteamApiClient apiClient,
    required RefreshCoordinator refreshCoordinator,
    ImageCacheService? imageCacheService,
  })  : _database = database,
        _profiles = profilesRepository,
        _activityRepo = activityRepository,
        _preferencesRepo = preferencesRepository,
        _keyStore = apiKeyStore,
        _api = apiClient,
        _coordinator = refreshCoordinator,
        _imageCache = imageCacheService ?? ImageCacheService();

  final AppDatabase _database;
  final ProfilesRepository _profiles;
  final ActivityRepository _activityRepo;
  final PreferencesRepository _preferencesRepo;
  final ApiKeyStore _keyStore;
  final SteamApiClient _api;
  final RefreshCoordinator _coordinator;
  final ImageCacheService _imageCache;

  // --- Estado ---------------------------------------------------------------

  bool _initialized = false;
  String? _initializationError;
  bool _hasApiKey = false;
  bool _demoMode = false;

  List<Profile> _realProfiles = <Profile>[];
  Map<String, ProfileActivity> _realActivities = <String, ProfileActivity>{};
  Preferences _preferences = const Preferences.defaults();

  AppSection _section = AppSection.recent;
  String _searchQuery = '';
  String? _filterSteamId;
  GameSortOrder _sortOrder = GameSortOrder.recent;

  final Set<String> _refreshing = <String>{};
  bool _refreshingAll = false;
  StreamSubscription<ProfileActivity>? _refreshSubscription;
  int _imageCacheBytes = 0;
  bool _disposed = false;

  // --- Lecturas -------------------------------------------------------------

  bool get initialized => _initialized;

  String? get initializationError => _initializationError;

  bool get hasApiKey => _hasApiKey;

  bool get demoMode => _demoMode;

  /// `true` cuando los datos mostrados son de demostración.
  bool get showingDemoData => _demoMode;

  Preferences get preferences => _preferences;

  AppSection get section => _section;

  String get searchQuery => _searchQuery;

  String? get filterSteamId => _filterSteamId;

  GameSortOrder get sortOrder => _sortOrder;

  bool get isRefreshingAll => _refreshingAll;

  bool isRefreshing(String steamId64) => _refreshing.contains(steamId64);

  int get imageCacheBytes => _imageCacheBytes;

  String get imageCacheSizeLabel => ImageCacheService.formatBytes(_imageCacheBytes);

  int get gamesStoredCount =>
      _realActivities.values.fold<int>(0, (int sum, ProfileActivity a) => sum + a.games.length);

  /// Perfiles visibles ahora mismo (reales o de demostración).
  List<Profile> get profiles =>
      _demoMode ? DemoData.profiles() : List<Profile>.unmodifiable(_realProfiles);

  /// Perfiles reales guardados en la base de datos.
  List<Profile> get realProfiles => List<Profile>.unmodifiable(_realProfiles);

  bool get hasRealProfiles => _realProfiles.isNotEmpty;

  Profile? get ownProfile {
    for (final Profile p in _realProfiles) {
      if (p.isOwnProfile) return p;
    }
    return null;
  }

  Profile? profileById(String steamId64) {
    for (final Profile p in profiles) {
      if (p.steamId64 == steamId64) return p;
    }
    return null;
  }

  /// Mapa de nombres a mostrar, usado por la agregación.
  Map<String, String> get displayNames => <String, String>{
        for (final Profile p in profiles) p.steamId64: p.displayName,
      };

  /// Actividad de un perfil (real o de demostración).
  ProfileActivity? activityFor(String steamId64) {
    if (_demoMode) return DemoData.activityFor(steamId64);
    return _realActivities[steamId64];
  }

  /// Actividades en el orden de la lista de perfiles.
  List<ProfileActivity> get allActivities {
    final List<ProfileActivity> result = <ProfileActivity>[];
    for (final Profile profile in profiles) {
      result.add(_decoratedActivity(profile));
    }
    return result;
  }

  ProfileActivity _decoratedActivity(Profile profile) {
    final ProfileActivity? stored = activityFor(profile.steamId64);
    if (stored == null) {
      return ProfileActivity(
        steamId64: profile.steamId64,
        personaName: profile.personaName,
        avatarUrl: profile.avatarUrl,
        status: FetchStatus.notFetched,
        isDemo: profile.isDemo,
      );
    }
    return stored.copyWith(
      personaName: stored.personaName ?? profile.personaName,
      avatarUrl: stored.avatarUrl ?? profile.avatarUrl,
      isDemo: stored.isDemo || profile.isDemo,
    );
  }

  /// Actividades listas para la pantalla Recientes (filtradas y ordenadas).
  List<ProfileActivity> get recentActivities {
    return filterAndSortActivities(
      activities: allActivities,
      displayNames: displayNames,
      query: _searchQuery,
      onlySteamId64: _filterSteamId,
      hideLowActivity: _preferences.hideLowActivity,
      lowActivityMinutes: _preferences.lowActivityFilterMinutes,
      order: _sortOrder,
    );
  }

  /// Juegos agregados por AppID para la pantalla General.
  List<AggregatedGame> get aggregatedGames {
    final List<ProfileActivity> source = <ProfileActivity>[];
    for (final ProfileActivity activity in allActivities) {
      source.add(
        _preferences.hideLowActivity
            ? activity.copyWith(
                games: activity.games
                    .where(
                      (Game g) =>
                          g.playtime2Weeks >= _preferences.lowActivityFilterMinutes,
                    )
                    .toList(growable: false),
              )
            : activity,
      );
    }
    final List<AggregatedGame> aggregated = aggregateByAppId(
      source,
      displayNames: displayNames,
      include: _filterSteamId == null
          ? null
          : (ProfileActivity a) => a.steamId64 == _filterSteamId,
    );
    return sortAggregatedGames(aggregated, _sortOrder);
  }

  /// Suma de minutos recientes de los perfiles visibles.
  int? get totalRecentMinutes => totalRecentMinutesOf(allActivities);

  /// Suma de minutos acumulados de los perfiles visibles.
  int? get totalForeverMinutes => totalForeverMinutesOf(allActivities);

  /// Juegos distintos entre todos los perfiles visibles.
  int get distinctGames => distinctGameCount(allActivities);

  /// `true` si procede mostrar el aviso de configuración pendiente.
  bool get needsSetup => !_hasApiKey && !_demoMode;

  /// Mensaje de la cabecera cuando falta configuración.
  String? get setupHint {
    if (_demoMode) return null;
    if (!_hasApiKey && _realProfiles.isEmpty) {
      return 'Añade integrantes o configura tu clave de Steam Web API.';
    }
    if (!_hasApiKey) return 'Falta la clave de Steam Web API.';
    if (_realProfiles.isEmpty) return 'Añade al menos un integrante.';
    return null;
  }

  // --- Inicialización -------------------------------------------------------

  /// Carga preferencias, clave y datos guardados.
  Future<void> initialize() async {
    try {
      _preferences = await _preferencesRepo.load();
      _hasApiKey = await _keyStore.hasApiKey();
      _api.setApiKey(_hasApiKey ? await _keyStore.loadApiKey() : null);
      _realProfiles = await _profiles.loadAll();
      _realActivities = await _activityRepo.loadAll();
      _section = _preferences.openLastViewedSection
          ? AppSection.fromName(_preferences.lastSection)
          : AppSection.recent;

      // Modo demostración: cuando no hay perfiles ni clave, o cuando el usuario
      // lo dejó activado.
      _demoMode = _preferences.demoModeEnabled ||
          (_realProfiles.isEmpty && !_hasApiKey);

      _initialized = true;
      _initializationError = null;
    } catch (e) {
      _initialized = true;
      _initializationError =
          'No se pudo preparar el almacenamiento local: $e';
    }
    _notify();

    if (_initializationError == null) {
      unawaited(_loadImageCacheSize());
      if (_preferences.refreshOnOpen && !_demoMode && _hasApiKey && _realProfiles.isNotEmpty) {
        unawaited(refreshAll(silent: true));
      }
    }
  }

  /// Reintenta la inicialización tras un fallo.
  Future<void> retryInitialize() => initialize();

  // --- Navegación y filtros -------------------------------------------------

  void setSection(AppSection section) {
    if (_section == section) return;
    _section = section;
    _preferences = _preferences.copyWith(lastSection: section.name);
    unawaited(_preferencesRepo.save(_preferences));
    _notify();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _notify();
  }

  void setFilterProfile(String? steamId64) {
    if (_filterSteamId == steamId64) return;
    _filterSteamId = steamId64;
    _notify();
  }

  void setSortOrder(GameSortOrder order) {
    if (_sortOrder == order) return;
    _sortOrder = order;
    _notify();
  }

  // --- Modo demostración ----------------------------------------------------

  Future<void> enterDemoMode() async {
    if (_demoMode) return;
    _demoMode = true;
    _preferences = _preferences.copyWith(demoModeEnabled: true);
    await _preferencesRepo.save(_preferences);
    _notify();
  }

  Future<void> exitDemoMode() async {
    if (!_demoMode) return;
    _demoMode = false;
    _preferences = _preferences.copyWith(demoModeEnabled: false);
    await _preferencesRepo.save(_preferences);
    _notify();
  }

  // --- Integrantes ----------------------------------------------------------

  /// Añade un integrante a partir de la entrada escrita por el usuario.
  ///
  /// Admite SteamID64, URL de perfil, URL de nombre personalizado y nombre
  /// personalizado resoluble mediante el endpoint documentado.
  Future<OperationResult> addProfileFromInput(String raw) async {
    final ProfileInputResult parsed = parseProfileInput(raw);
    if (!parsed.isValid) {
      return OperationResult.error(parsed.errorEs ?? 'Entrada no válida.');
    }
    final ParsedProfileInput input = parsed.input!;

    String steamId64;
    if (input.isSteamId64) {
      steamId64 = input.value;
    } else {
      if (!_hasApiKey) {
        return const OperationResult.error(
          'Para resolver un nombre personalizado hace falta una clave de Steam '
          'Web API configurada. También puedes pegar la URL completa del perfil '
          'o su SteamID64 de 17 dígitos.',
        );
      }
      try {
        final VanityResolution resolution = await _api.resolveVanityUrl(input.value);
        if (!resolution.success || resolution.steamId64 == null) {
          return OperationResult.error(
            resolution.messageEs ?? 'No se pudo resolver ese nombre personalizado.',
          );
        }
        steamId64 = resolution.steamId64!;
      } on SteamApiException catch (e) {
        return OperationResult.error(e.messageEs);
      }
    }

    if (DemoData.isDemoSteamId(steamId64) || DemoData.looksLikeDemo(steamId64)) {
      return const OperationResult.error(
        'Ese identificador está reservado para el modo demostración. Usa el '
        'SteamID64 real del perfil.',
      );
    }

    if (await _profiles.exists(steamId64)) {
      return const OperationResult.error(
        'Ese perfil ya está en tu lista de integrantes.',
      );
    }

    String? personaName;
    String? avatarUrl;
    String note = '';
    if (_hasApiKey) {
      try {
        final List<SteamPlayerSummary> summaries =
            await _api.fetchPlayerSummaries(<String>[steamId64]);
        if (summaries.isEmpty) {
          return OperationResult.error(
            'Steam no reconoce el SteamID64 $steamId64. Comprueba que la '
            'cuenta existe.',
          );
        }
        personaName = summaries.first.personaName;
        avatarUrl = summaries.first.avatarUrl;
        if (personaName == null) {
          note = ' Steam no ha comunicado un nombre público para ese perfil.';
        }
      } on SteamApiException catch (e) {
        note = ' No se pudieron obtener el nombre y el avatar (${e.messageEs})';
      }
    } else {
      note = ' Añade tu clave de Web API en Ajustes para ver su nombre y avatar '
          'y consultar su actividad.';
    }

    final Profile profile = Profile(
      steamId64: steamId64,
      personaName: personaName,
      avatarUrl: avatarUrl,
      createdAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _profiles.upsert(profile);
    _realProfiles = await _profiles.loadAll();

    if (_demoMode) {
      // Al añadir datos propios se abandona el modo demostración.
      _demoMode = false;
      _preferences = _preferences.copyWith(demoModeEnabled: false);
      await _preferencesRepo.save(_preferences);
    }

    _notify();
    return OperationResult.ok('Integrante añadido.$note', steamId64: steamId64);
  }

  /// Guarda los cambios de edición de un perfil (alias y perfil propio).
  Future<OperationResult> updateProfile({
    required String steamId64,
    String? alias,
    bool? isOwnProfile,
  }) async {
    final String? aliasError = validateAlias(alias);
    if (aliasError != null) return OperationResult.error(aliasError);

    final Profile? current = await _profiles.findById(steamId64);
    if (current == null) {
      return const OperationResult.error('Ese perfil ya no existe.');
    }

    final String? trimmedAlias = alias?.trim();
    await _profiles.upsert(
      current.copyWith(
        alias: (trimmedAlias == null || trimmedAlias.isEmpty) ? null : trimmedAlias,
        clearAlias: trimmedAlias == null || trimmedAlias.isEmpty,
      ),
    );
    if (isOwnProfile != null) {
      await _profiles.setOwnProfile(isOwnProfile ? steamId64 : null);
    }
    _realProfiles = await _profiles.loadAll();
    _notify();
    return const OperationResult.ok('Integrante actualizado.');
  }

  /// Elimina un perfil y su actividad.
  Future<OperationResult> deleteProfile(String steamId64) async {
    await _profiles.delete(steamId64);
    _realActivities.remove(steamId64);
    _realProfiles = await _profiles.loadAll();
    if (_filterSteamId == steamId64) _filterSteamId = null;
    if (_preferences.lastSelectedProfile == steamId64) {
      _preferences = _preferences.copyWith(clearLastSelectedProfile: true);
      await _preferencesRepo.save(_preferences);
    }
    _notify();
    return const OperationResult.ok('Integrante eliminado.');
  }

  Future<void> setOwnProfile(String? steamId64) async {
    await _profiles.setOwnProfile(steamId64);
    _realProfiles = await _profiles.loadAll();
    _notify();
  }

  // --- Actualizaciones ------------------------------------------------------

  /// Actualiza un perfil concreto sin bloquear la interfaz.
  Future<void> refreshProfile(String steamId64) async {
    final Profile? profile = profileById(steamId64);
    if (profile == null) return;
    if (profile.isDemo) {
      // Los datos de demostración son locales: no hay nada que actualizar.
      _notify();
      return;
    }
    if (_refreshing.contains(steamId64)) return;

    _refreshing.add(steamId64);
    _notify();
    try {
      final ProfileActivity activity = await _coordinator.refreshProfile(
        profile,
        previous: _realActivities[steamId64],
      );
      if (_disposed) return;
      _realActivities[steamId64] = activity;
    } finally {
      _refreshing.remove(steamId64);
      _notify();
    }
  }

  /// Actualiza todos los perfiles reales emitiendo resultados parciales.
  Future<void> refreshAll({bool silent = false}) async {
    if (_refreshingAll || _disposed) return;

    final List<Profile> targets =
        _realProfiles.where((Profile p) => !p.isDemo).toList(growable: false);
    if (targets.isEmpty) {
      // No hay perfiles reales: los datos de demostración son locales, así que
      // no hay nada que actualizar por red.
      if (!silent) _notify();
      return;
    }

    _refreshingAll = true;
    _notify();

    final Completer<void> done = Completer<void>();
    final Map<String, ProfileActivity> cached = <String, ProfileActivity>{
      for (final Profile p in targets)
        if (_realActivities[p.steamId64] != null) p.steamId64: _realActivities[p.steamId64]!,
    };

    await _refreshSubscription?.cancel();
    _refreshSubscription = _coordinator
        .refreshAll(targets, cached: cached)
        .listen(
      (ProfileActivity activity) {
        if (_disposed) return;
        _realActivities[activity.steamId64] = activity;
        _notify();
      },
      onError: (Object error) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        _refreshingAll = false;
        if (!done.isCompleted) done.complete();
        _notify();
      },
      cancelOnError: false,
    );

    return done.future;
  }

  /// Cancela una actualización global en curso.
  Future<void> cancelRefresh() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    if (_refreshingAll) {
      _refreshingAll = false;
      _notify();
    }
  }

  // --- Clave de API ---------------------------------------------------------

  /// Guarda la clave en el almacenamiento seguro.
  Future<OperationResult> saveApiKey(String apiKey) async {
    final String? formatError = validateApiKeyFormat(apiKey);
    if (formatError != null) return OperationResult.error(formatError);

    await _keyStore.saveApiKey(apiKey);
    _api.setApiKey(await _keyStore.loadApiKey());
    _hasApiKey = await _keyStore.hasApiKey();
    if (_demoMode && _hasApiKey) {
      // Al configurar una clave ya no tiene sentido arrancar en demostración.
      _demoMode = _preferences.demoModeEnabled;
    }
    _notify();
    return const OperationResult.ok(
      'Clave guardada en el almacenamiento seguro del dispositivo.',
    );
  }

  /// Elimina la clave del almacenamiento seguro.
  Future<OperationResult> deleteApiKey() async {
    await _keyStore.deleteApiKey();
    _api.setApiKey(null);
    _hasApiKey = false;
    _notify();
    return const OperationResult.ok('Clave eliminada del dispositivo.');
  }

  /// Comprueba si la clave configurada es aceptada por Steam.
  Future<ApiKeyCheckResult> verifyApiKey() {
    return _api.verifyApiKey(steamId64: ownProfile?.steamId64);
  }

  // --- Preferencias y caché -------------------------------------------------

  Future<void> savePreferences(Preferences preferences) async {
    final Preferences safe = preferences.sanitized();
    _preferences = safe;
    await _preferencesRepo.save(safe);
    _notify();
  }

  Future<void> resetPreferences() async {
    _preferences = await _preferencesRepo.reset();
    _notify();
  }

  /// Borra la actividad en caché conservando la lista de integrantes.
  Future<OperationResult> clearActivityCache() async {
    await _database.clearUserData(includeProfiles: false);
    _realActivities = <String, ProfileActivity>{};
    _notify();
    return const OperationResult.ok(
      'Caché de actividad borrada. Los integrantes se han conservado.',
    );
  }

  /// Borra la caché de imágenes.
  Future<OperationResult> clearImageCache() async {
    final bool ok = await _imageCache.clearCache();
    await _loadImageCacheSize();
    return OperationResult(
      success: ok,
      messageEs: ok
          ? 'Caché de imágenes borrada.'
          : 'No se pudo borrar por completo la caché de imágenes.',
    );
  }

  Future<void> _loadImageCacheSize() async {
    _imageCacheBytes = await _imageCache.cacheSizeBytes();
    if (!_disposed) _notify();
  }

  Future<void> refreshImageCacheSize() => _loadImageCacheSize();

  // --- Importación de amigos ------------------------------------------------

  /// Carga la lista de amigos del perfil propio.
  Future<FriendImportResult> loadFriends() async {
    if (!_hasApiKey) {
      return const FriendImportResult(
        friends: <SteamPlayerSummary>[],
        messageEs: 'Necesitas una clave de Steam Web API configurada para '
            'importar amigos.',
        isError: true,
      );
    }
    final Profile? own = ownProfile;
    if (own == null) {
      return const FriendImportResult(
        friends: <SteamPlayerSummary>[],
        messageEs: 'Marca primero tu perfil propio en Integrantes: la API de '
            'Steam necesita ese SteamID64 para consultar la lista de amigos.',
        isError: true,
      );
    }

    try {
      final List<String> ids = await _api.fetchFriendList(own.steamId64);
      if (ids.isEmpty) {
        return const FriendImportResult(
          friends: <SteamPlayerSummary>[],
          messageEs: 'Steam no ha devuelto ningún amigo. Esto ocurre cuando la '
              'lista de amigos no es pública para la clave configurada.',
          isError: false,
        );
      }
      final List<SteamPlayerSummary> summaries =
          await _api.fetchPlayerSummaries(ids);
      return FriendImportResult(
        friends: summaries,
        messageEs: 'Se han encontrado ${summaries.length} amigos.',
        isError: false,
      );
    } on SteamApiException catch (e) {
      final String extra = e.kind == SteamApiErrorKind.privateOrUnavailable
          ? ' Si la lista es privada, añade los integrantes manualmente.'
          : '';
      return FriendImportResult(
        friends: const <SteamPlayerSummary>[],
        messageEs: '${e.messageEs}$extra',
        isError: true,
      );
    }
  }

  /// Añade los amigos seleccionados, omitiendo los que ya existan.
  Future<OperationResult> addImportedProfiles(
    List<SteamPlayerSummary> summaries,
  ) async {
    int added = 0;
    int skipped = 0;
    final Set<String> existing = _realProfiles.map((Profile p) => p.steamId64).toSet();
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final SteamPlayerSummary summary in summaries) {
      if (existing.contains(summary.steamId64)) {
        skipped++;
        continue;
      }
      await _profiles.upsert(
        Profile(
          steamId64: summary.steamId64,
          personaName: summary.personaName,
          avatarUrl: summary.avatarUrl,
          createdAtUnix: now + added,
        ),
      );
      existing.add(summary.steamId64);
      added++;
    }
    _realProfiles = await _profiles.loadAll();
    _notify();
    return OperationResult.ok(
      'Se han añadido $added integrantes.'
      '${skipped > 0 ? ' $skipped ya estaban en la lista.' : ''}',
    );
  }

  // --- Utilidades -----------------------------------------------------------

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshSubscription?.cancel();
    _coordinator.dispose();
    _api.dispose();
    unawaited(_database.close());
    super.dispose();
  }
}

/// Punto de acceso al controlador desde el árbol de widgets.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final AppScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado en el árbol de widgets.');
    return scope!.notifier!;
  }
}

/// Textos de la aplicación que dependen de constantes.
class WatapTexts {
  const WatapTexts._();

  static const String appName = AppConstants.appName;
  static const String subtitle = AppConstants.appSubtitle;
}
