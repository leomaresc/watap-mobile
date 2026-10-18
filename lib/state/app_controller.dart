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
import '../data/local/steam_token_store.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/profiles_repository.dart';
import '../data/steam/family_groups_client.dart';
import '../data/steam/steam_api_client.dart';
import '../data/steam/steam_api_errors.dart';
import '../services/activity_aggregator.dart';
import '../services/family_group_sync.dart';
import '../services/refresh_coordinator.dart';

/// Secciones de la navegación inferior.
enum AppSection {
  /// Juegos recientes agrupados por integrante.
  recent,

  /// Actividad agregada de todos los integrantes.
  overview,

  /// Integrantes supervisados.
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

/// Resultado de importar una lista de integrantes.
class ImportResult {
  const ImportResult({
    required this.added,
    required this.skipped,
    required this.failed,
    required this.messageEs,
    this.isError = false,
  });

  final int added;
  final int skipped;
  final int failed;
  final String messageEs;
  final bool isError;
}

/// Controlador principal de WATAP Mobile.
class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required ProfilesRepository profilesRepository,
    required ActivityRepository activityRepository,
    required PreferencesRepository preferencesRepository,
    required ApiKeyStore apiKeyStore,
    required SteamTokenStore tokenStore,
    required SteamApiClient apiClient,
    required FamilyGroupsClient familyGroupsClient,
    required FamilyGroupSyncService familySyncService,
    required RefreshCoordinator refreshCoordinator,
    ImageCacheService? imageCacheService,
  })  : _database = database,
        _profiles = profilesRepository,
        _activityRepo = activityRepository,
        _preferencesRepo = preferencesRepository,
        _keyStore = apiKeyStore,
        _tokenStore = tokenStore,
        _api = apiClient,
        _groups = familyGroupsClient,
        _familySync = familySyncService,
        _coordinator = refreshCoordinator,
        _imageCache = imageCacheService ?? ImageCacheService();

  final AppDatabase _database;
  final ProfilesRepository _profiles;
  final ActivityRepository _activityRepo;
  final PreferencesRepository _preferencesRepo;
  final ApiKeyStore _keyStore;
  final SteamTokenStore _tokenStore;
  final SteamApiClient _api;
  final FamilyGroupsClient _groups;
  final FamilyGroupSyncService _familySync;
  final RefreshCoordinator _coordinator;
  final ImageCacheService _imageCache;

  // --- Estado ---------------------------------------------------------------

  bool _initialized = false;
  String? _initializationError;
  bool _hasApiKey = false;
  bool _hasFamilyToken = false;
  String? _familyGroupName;
  int? _lastFamilySyncUnix;
  bool _syncingFamily = false;

  List<Profile> _profilesList = <Profile>[];
  Map<String, ProfileActivity> _activities = <String, ProfileActivity>{};
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

  /// `true` cuando hay un token de sesión de Steam guardado.
  ///
  /// Ese token es el que permite leer el grupo familiar; la clave de Web API no
  /// sirve para eso.
  bool get hasFamilyToken => _hasFamilyToken;

  /// Nombre del grupo familiar, en la última sincronización correcta.
  String? get familyGroupName => _familyGroupName;

  /// Marca de tiempo (segundos) de la última sincronización correcta.
  int? get lastFamilySyncUnix => _lastFamilySyncUnix;

  bool get isSyncingFamily => _syncingFamily;

  /// `true` cuando la aplicación tiene todo lo necesario para funcionar.
  ///
  /// Se exige además haber pasado el paso del grupo familiar (conectado u
  /// omitido explícitamente), para no bloquear si la conexión con Steam falla.
  bool get onboardingComplete =>
      _hasApiKey && (_hasFamilyToken || _preferences.familySetupDone);

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
      _activities.values.fold<int>(0, (int sum, ProfileActivity a) => sum + a.games.length);

  /// Todos los perfiles guardados.
  List<Profile> get profiles => List<Profile>.unmodifiable(_profilesList);

  /// Perfiles importados del grupo familiar de Steam.
  List<Profile> get familyMembers => List<Profile>.unmodifiable(
        _profilesList.where((Profile p) => p.isFamilyMember),
      );

  bool get hasProfiles => _profilesList.isNotEmpty;

  Profile? profileById(String steamId64) {
    for (final Profile p in _profilesList) {
      if (p.steamId64 == steamId64) return p;
    }
    return null;
  }

  /// Mapa de nombres a mostrar, usado por la agregación.
  Map<String, String> get displayNames => <String, String>{
        for (final Profile p in _profilesList) p.steamId64: p.displayName,
      };

  ProfileActivity? activityFor(String steamId64) => _activities[steamId64];

  /// Actividades en el orden de la lista de perfiles.
  List<ProfileActivity> get allActivities {
    final List<ProfileActivity> result = <ProfileActivity>[];
    for (final Profile profile in _profilesList) {
      result.add(_decoratedActivity(profile));
    }
    return result;
  }

  ProfileActivity _decoratedActivity(Profile profile) {
    final ProfileActivity? stored = _activities[profile.steamId64];
    if (stored == null) {
      return ProfileActivity(
        steamId64: profile.steamId64,
        personaName: profile.personaName,
        avatarUrl: profile.avatarUrl,
        status: FetchStatus.notFetched,
      );
    }
    return stored.copyWith(
      personaName: stored.personaName ?? profile.personaName,
      avatarUrl: stored.avatarUrl ?? profile.avatarUrl,
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

  // --- Inicialización -------------------------------------------------------

  /// Carga preferencias, credenciales y datos guardados.
  Future<void> initialize() async {
    try {
      _preferences = await _preferencesRepo.load();
      _hasApiKey = await _keyStore.hasApiKey();
      _api.setApiKey(_hasApiKey ? await _keyStore.loadApiKey() : null);
      _hasFamilyToken = (await _tokenStore.load()) != null;
      _profilesList = await _profiles.loadAll();
      _activities = await _activityRepo.loadAll();
      _section = _preferences.openLastViewedSection
          ? AppSection.fromName(_preferences.lastSection)
          : AppSection.recent;

      _initialized = true;
      _initializationError = null;
    } catch (e) {
      _initialized = true;
      _initializationError = 'No se pudo preparar el almacenamiento local: $e';
    }
    _notify();

    if (_initializationError == null) {
      unawaited(_loadImageCacheSize());
      if (_preferences.refreshOnOpen && onboardingComplete && hasProfiles) {
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

  // --- Conexión con Steam y grupo familiar ----------------------------------

  /// Guarda el `webapi_token` obtenido desde la página de Steam.
  ///
  /// El token se escribe **solo** en el almacenamiento seguro del dispositivo.
  Future<void> saveFamilyToken(String token) async {
    final String trimmed = token.trim();
    if (trimmed.isEmpty) return;
    await _tokenStore.save(trimmed);
    _hasFamilyToken = true;
    _notify();
  }

  /// Elimina el token de Steam del dispositivo.
  Future<OperationResult> disconnectSteam() async {
    await _tokenStore.clear();
    _hasFamilyToken = false;
    _familyGroupName = null;
    _lastFamilySyncUnix = null;
    _notify();
    return const OperationResult.ok(
      'Conexión con Steam eliminada del dispositivo. Tus integrantes guardados '
      'se conservan.',
    );
  }

  /// Marca el paso del grupo familiar como completado sin conectar.
  ///
  /// Sirve de escape si la página de Steam no carga: la aplicación no debe
  /// quedar bloqueada. Puede conectarse más tarde desde Integrantes o Ajustes.
  Future<void> skipFamilySetup() async {
    if (_preferences.familySetupDone) return;
    _preferences = _preferences.copyWith(familySetupDone: true);
    await _preferencesRepo.save(_preferences);
    _notify();
  }

  /// Sincroniza la lista de integrantes con el grupo familiar de Steam.
  Future<FamilySyncOutcome> syncFamilyGroup({bool silent = false}) async {
    if (_syncingFamily) {
      return const FamilySyncOutcome.failure(
        'Ya hay una sincronización del grupo familiar en curso.',
      );
    }
    if (!_hasApiKey) {
      return const FamilySyncOutcome.failure(
        'Configura la clave de Steam Web API antes de sincronizar.',
      );
    }

    _syncingFamily = true;
    if (!silent) _notify();
    try {
      final String? token = await _tokenStore.load();
      final FamilySyncOutcome outcome =
          await _familySync.sync(token ?? '');

      if (outcome.success) {
        _familyGroupName = outcome.groupName ?? _familyGroupName;
        _lastFamilySyncUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _profilesList = await _profiles.loadAll();
        // La primera sincronización correcta da por superado el asistente.
        if (!_preferences.familySetupDone) {
          _preferences = _preferences.copyWith(familySetupDone: true);
          await _preferencesRepo.save(_preferences);
        }
      } else if (outcome.requiresConnect) {
        // El token ya no sirve: se borra para que la interfaz ofrezca volver a
        // conectar en lugar de reintentar en vano.
        await _tokenStore.clear();
        _hasFamilyToken = false;
      }
      return outcome;
    } finally {
      _syncingFamily = false;
      _notify();
    }
  }

  // --- Integrantes ----------------------------------------------------------

  /// Importa una lista de perfiles de una sola vez.
  ///
  /// Cada entrada puede ser un SteamID64, una URL de perfil de Steam o un
  /// nombre personalizado. Las entradas inválidas o duplicadas se omiten.
  Future<ImportResult> importMembers(List<String> rawEntries) async {
    if (!_hasApiKey) {
      return const ImportResult(
        added: 0,
        skipped: 0,
        failed: 0,
        messageEs: 'Necesitas una clave de Steam Web API configurada para '
            'importar integrantes.',
        isError: true,
      );
    }

    final Set<String> existing =
        _profilesList.map((Profile p) => p.steamId64).toSet();
    final List<String> parsedIds = <String>[];
    int failed = 0;

    for (final String raw in rawEntries) {
      final ProfileInputResult result = parseProfileInput(raw);
      if (!result.isValid) {
        failed++;
        continue;
      }
      final ParsedProfileInput input = result.input!;

      String steamId64;
      if (input.isSteamId64) {
        steamId64 = input.value;
      } else {
        try {
          final VanityResolution resolution =
              await _api.resolveVanityUrl(input.value);
          if (!resolution.success || resolution.steamId64 == null) {
            failed++;
            continue;
          }
          steamId64 = resolution.steamId64!;
        } on SteamApiException {
          failed++;
          continue;
        }
      }

      if (!existing.contains(steamId64)) {
        parsedIds.add(steamId64);
        existing.add(steamId64);
      }
    }

    if (parsedIds.isEmpty) {
      return ImportResult(
        added: 0,
        skipped: 0,
        failed: failed,
        messageEs: failed > 0
            ? 'Ninguna entrada válida. Se descartaron $failed entradas.'
            : 'No se encontraron perfiles nuevos.',
        isError: failed > 0,
      );
    }

    int added = 0;
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final String id in parsedIds) {
      await _profiles.upsert(
        Profile(steamId64: id, createdAtUnix: now + added),
      );
      added++;
    }

    // Se obtienen nombres y avatares en lote.
    try {
      final List<SteamPlayerSummary> summaries =
          await _api.fetchPlayerSummaries(parsedIds);
      for (final SteamPlayerSummary s in summaries) {
        await _profiles.applySummary(s);
      }
    } on SteamApiException {
      // Los nombres se completarán al actualizar la actividad.
    }

    _profilesList = await _profiles.loadAll();
    _notify();

    final List<String> parts = <String>[];
    if (added > 0) parts.add('$added añadidos');
    if (failed > 0) parts.add('$failed descartados');
    return ImportResult(
      added: added,
      skipped: 0,
      failed: failed,
      messageEs: 'Importación completada: ${parts.join(', ')}.',
    );
  }

  /// Añade un perfil individual (vía manual, para excepciones).
  Future<OperationResult> addProfile(String raw) async {
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
          'Web API configurada.',
        );
      }
      try {
        final VanityResolution resolution =
            await _api.resolveVanityUrl(input.value);
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

    if (await _profiles.exists(steamId64)) {
      return const OperationResult.error('Ese perfil ya está en tu lista.');
    }

    String? personaName;
    String? avatarUrl;
    if (_hasApiKey) {
      try {
        final List<SteamPlayerSummary> summaries =
            await _api.fetchPlayerSummaries(<String>[steamId64]);
        if (summaries.isNotEmpty) {
          personaName = summaries.first.personaName;
          avatarUrl = summaries.first.avatarUrl;
        }
      } on SteamApiException {
        // Se añade sin nombre; se completará al actualizar.
      }
    }

    await _profiles.upsert(
      Profile(
        steamId64: steamId64,
        personaName: personaName,
        avatarUrl: avatarUrl,
        createdAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    _profilesList = await _profiles.loadAll();
    _notify();
    return OperationResult.ok('Perfil añadido.', steamId64: steamId64);
  }

  /// Guarda los cambios de edición de un perfil (alias).
  Future<OperationResult> updateProfile({
    required String steamId64,
    String? alias,
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
    _profilesList = await _profiles.loadAll();
    _notify();
    return const OperationResult.ok('Integrante actualizado.');
  }

  /// Elimina un perfil y su actividad.
  Future<OperationResult> deleteProfile(String steamId64) async {
    await _profiles.delete(steamId64);
    _activities.remove(steamId64);
    _profilesList = await _profiles.loadAll();
    if (_filterSteamId == steamId64) _filterSteamId = null;
    if (_preferences.lastSelectedProfile == steamId64) {
      _preferences = _preferences.copyWith(clearLastSelectedProfile: true);
      await _preferencesRepo.save(_preferences);
    }
    _notify();
    return const OperationResult.ok('Integrante eliminado.');
  }

  // --- Actualizaciones ------------------------------------------------------

  /// Actualiza un perfil concreto sin bloquear la interfaz.
  Future<void> refreshProfile(String steamId64) async {
    final Profile? profile = profileById(steamId64);
    if (profile == null) return;
    if (_refreshing.contains(steamId64)) return;

    _refreshing.add(steamId64);
    _notify();
    try {
      final ProfileActivity activity = await _coordinator.refreshProfile(
        profile,
        previous: _activities[steamId64],
      );
      if (_disposed) return;
      _activities[steamId64] = activity;
    } finally {
      _refreshing.remove(steamId64);
      _notify();
    }
  }

  /// Actualiza todos los perfiles emitiendo resultados parciales.
  Future<void> refreshAll({bool silent = false}) async {
    if (_refreshingAll || _disposed) return;

    final List<Profile> targets = List<Profile>.of(_profilesList);
    if (targets.isEmpty) {
      if (!silent) _notify();
      return;
    }

    _refreshingAll = true;
    _notify();

    final Completer<void> done = Completer<void>();
    final Map<String, ProfileActivity> cached = <String, ProfileActivity>{
      for (final Profile p in targets)
        if (_activities[p.steamId64] != null) p.steamId64: _activities[p.steamId64]!,
    };

    await _refreshSubscription?.cancel();
    _refreshSubscription = _coordinator
        .refreshAll(targets, cached: cached)
        .listen(
      (ProfileActivity activity) {
        if (_disposed) return;
        _activities[activity.steamId64] = activity;
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
    return _api.verifyApiKey();
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
    _activities = <String, ProfileActivity>{};
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
    _groups.dispose();
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