/// Estado de la aplicación.
///
/// Se usa `ChangeNotifier` del SDK (sin dependencias adicionales de gestión de
/// estado) expuesto mediante un `InheritedNotifier`. Toda la lógica de negocio
/// vive en los servicios y repositorios; este controlador solo los coordina y
/// mantiene el estado observable por la interfaz.
///
/// WATAP necesita **dos** credenciales, y ambas viven fuera de la base de datos:
/// 1. La clave de Steam Web API (almacenamiento seguro), con la que se consulta
///    la actividad pública de cada integrante.
/// 2. La sesión de Steam (`access_token` + `refresh_token`), también en el
///    almacenamiento seguro, con la que se lee el grupo familiar.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/constants.dart';
import '../core/models.dart';
import '../core/validators.dart';
import '../data/local/app_database.dart';
import '../data/local/image_cache_service.dart';
import '../data/local/secure_api_key_store.dart';
import '../data/local/steam_session_store.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/profiles_repository.dart';
import '../data/steam/family_groups_client.dart';
import '../data/steam/steam_api_client.dart';
import '../data/steam/steam_api_errors.dart';
import '../data/steam/steam_auth_client.dart';
import '../services/activity_aggregator.dart';
import '../services/family_group_sync.dart';
import '../services/refresh_coordinator.dart';

/// Secciones de la navegación inferior.
enum AppSection {
  /// Juegos recientes agrupados por integrante.
  recent,

  /// Actividad agregada de todos los integrantes.
  overview,

  /// Integrantes del grupo familiar.
  members,

  /// Credenciales, preferencias, caché y privacidad.
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
        AppSection.members => 'Familia',
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

/// Resultado del primer paso del inicio de sesión en Steam.
class SteamLoginStep {
  const SteamLoginStep({
    required this.success,
    required this.messageEs,
    this.challenge,
  });

  final bool success;
  final String messageEs;

  /// Desafío que debe continuar la interfaz (código de Steam Guard o espera de
  /// confirmación desde el móvil). `null` si no se pudo iniciar el acceso.
  final SteamLoginChallenge? challenge;

  /// `true` cuando Steam exige que el usuario escriba un código.
  bool get needsGuardCode => challenge?.needsGuardCode ?? false;
}

/// Controlador principal de WATAP Mobile.
class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required ProfilesRepository profilesRepository,
    required ActivityRepository activityRepository,
    required PreferencesRepository preferencesRepository,
    required ApiKeyStore apiKeyStore,
    required SteamSessionStore sessionStore,
    required SteamApiClient apiClient,
    required SteamAuthClient authClient,
    required FamilyGroupsClient familyGroupsClient,
    required FamilyGroupSyncService familySyncService,
    required RefreshCoordinator refreshCoordinator,
    ImageCacheService? imageCacheService,
  })  : _database = database,
        _profiles = profilesRepository,
        _activityRepo = activityRepository,
        _preferencesRepo = preferencesRepository,
        _keyStore = apiKeyStore,
        _sessionStore = sessionStore,
        _api = apiClient,
        _auth = authClient,
        _groups = familyGroupsClient,
        _familySync = familySyncService,
        _coordinator = refreshCoordinator,
        _imageCache = imageCacheService ?? ImageCacheService();

  final AppDatabase _database;
  final ProfilesRepository _profiles;
  final ActivityRepository _activityRepo;
  final PreferencesRepository _preferencesRepo;
  final ApiKeyStore _keyStore;
  final SteamSessionStore _sessionStore;
  final SteamApiClient _api;
  final SteamAuthClient _auth;
  final FamilyGroupsClient _groups;
  final FamilyGroupSyncService _familySync;
  final RefreshCoordinator _coordinator;
  final ImageCacheService _imageCache;

  // --- Estado ---------------------------------------------------------------

  bool _initialized = false;
  String? _initializationError;
  bool _hasApiKey = false;
  SteamSession? _session;

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

  bool _syncingFamily = false;
  String? _familyGroupName;
  int? _lastFamilySyncUnix;

  // --- Lecturas -------------------------------------------------------------

  bool get initialized => _initialized;

  String? get initializationError => _initializationError;

  bool get hasApiKey => _hasApiKey;

  /// `true` cuando hay una sesión de Steam guardada.
  bool get hasSteamSession => _session != null;

  /// Nombre de la cuenta de Steam conectada, si Steam lo comunicó.
  String? get steamAccountName => _session?.accountName;

  /// SteamID64 de la cuenta conectada.
  String? get steamId64 => _session?.steamId64;

  /// `true` cuando la aplicación tiene todo lo necesario para funcionar.
  ///
  /// Mientras sea `false`, la interfaz muestra el asistente de configuración en
  /// lugar del panel principal.
  bool get onboardingComplete => _hasApiKey && _session != null;

  /// Nombre del grupo familiar, tal como lo devolvió Steam en la última
  /// sincronización correcta.
  String? get familyGroupName => _familyGroupName;

  /// Marca de tiempo (segundos) de la última sincronización correcta.
  int? get lastFamilySyncUnix => _lastFamilySyncUnix;

  bool get isSyncingFamily => _syncingFamily;

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

  /// Todos los perfiles guardados (integrantes del grupo y perfiles de rescate).
  List<Profile> get profiles => List<Profile>.unmodifiable(_profilesList);

  /// Integrantes obtenidos automáticamente del grupo familiar.
  List<Profile> get familyMembers => List<Profile>.unmodifiable(
        _profilesList.where((Profile p) => p.isFamilyMember),
      );

  /// Perfiles añadidos a mano como excepción.
  List<Profile> get rescueProfiles => List<Profile>.unmodifiable(
        _profilesList.where((Profile p) => !p.isFamilyMember),
      );

  bool get hasProfiles => _profilesList.isNotEmpty;

  /// Cuenta conectada, si está entre los integrantes.
  Profile? get ownProfile {
    final String? id = _session?.steamId64;
    for (final Profile p in _profilesList) {
      if (id != null && p.steamId64 == id) return p;
    }
    for (final Profile p in _profilesList) {
      if (p.isOwnProfile) return p;
    }
    return null;
  }

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
      _session = await _sessionStore.load();
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

  // --- Sesión de Steam ------------------------------------------------------

  /// Primer paso del acceso: valida cuenta y contraseña contra Steam.
  ///
  /// La contraseña se cifra con la clave pública de Steam y no se guarda.
  Future<SteamLoginStep> beginSteamLogin({
    required String accountName,
    required String password,
  }) async {
    try {
      final SteamLoginChallenge challenge = await _auth.beginLogin(
        accountName: accountName,
        password: password,
      );
      return SteamLoginStep(
        success: true,
        messageEs: challenge.needsGuardCode
            ? 'Steam ha pedido un código de Steam Guard para esta cuenta.'
            : 'Steam ha enviado una confirmación. Acéptala en tu teléfono con '
                'la aplicación de Steam.',
        challenge: challenge,
      );
    } on SteamApiException catch (e) {
      return SteamLoginStep(success: false, messageEs: e.messageEs);
    } catch (e) {
      return const SteamLoginStep(
        success: false,
        messageEs: 'No se pudo iniciar sesión en Steam.',
      );
    }
  }

  /// Envía el código de Steam Guard y completa el acceso.
  Future<OperationResult> submitSteamGuardCode({
    required SteamLoginChallenge challenge,
    required String code,
  }) async {
    try {
      final SteamSession session = await _auth.submitGuardCode(
        challenge: challenge,
        code: code,
      );
      return await _activateSession(session);
    } on SteamApiException catch (e) {
      return OperationResult.error(e.messageEs);
    } catch (e) {
      return const OperationResult.error(
        'No se pudo completar el acceso con Steam.',
      );
    }
  }

  /// Espera a que el usuario confirme el acceso desde su teléfono.
  Future<OperationResult> waitForSteamConfirmation(
    SteamLoginChallenge challenge,
  ) async {
    try {
      final SteamSession session = await _auth.pollStatus(challenge);
      return await _activateSession(session);
    } on SteamApiException catch (e) {
      return OperationResult.error(e.messageEs);
    } catch (e) {
      return const OperationResult.error(
        'No se pudo confirmar el acceso con Steam.',
      );
    }
  }

  /// Guarda la sesión y sincroniza el grupo familiar.
  Future<OperationResult> _activateSession(SteamSession session) async {
    await _sessionStore.save(session);
    _session = session;
    _notify();

    final FamilySyncOutcome outcome = await syncFamilyGroup(silent: true);
    if (outcome.success) {
      return OperationResult.ok(outcome.messageEs);
    }
    return OperationResult(
      success: true,
      messageEs: 'Sesión de Steam iniciada como '
          '${session.accountName ?? session.steamId64}. '
          '${outcome.messageEs}',
    );
  }

  /// Cierra la sesión de Steam y borra los tokens del dispositivo.
  Future<OperationResult> logoutSteam() async {
    await _sessionStore.clear();
    _session = null;
    _familyGroupName = null;
    _lastFamilySyncUnix = null;
    _notify();
    return const OperationResult.ok(
      'Sesión de Steam cerrada y tokens eliminados del dispositivo.',
    );
  }

  // --- Grupo familiar -------------------------------------------------------

  /// Sincroniza la lista de integrantes con el grupo familiar de Steam.
  ///
  /// Si el token de acceso ha caducado, intenta renovarlo con el
  /// `refresh_token` antes de darse por vencida.
  Future<FamilySyncOutcome> syncFamilyGroup({bool silent = false}) async {
    final SteamSession? session = _session;
    if (session == null) {
      return const FamilySyncOutcome.failure(
        'Conecta tu cuenta de Steam para leer el grupo familiar.',
        requiresLogin: true,
      );
    }
    if (_syncingFamily) {
      return const FamilySyncOutcome.failure(
        'Ya hay una sincronización del grupo familiar en curso.',
      );
    }

    _syncingFamily = true;
    if (!silent) _notify();
    try {
      FamilySyncOutcome outcome = await _familySync.sync(session);

      if (!outcome.success && outcome.requiresLogin) {
        // Un intento de renovación silenciosa antes de pedir la contraseña otra
        // vez.
        try {
          final SteamSession renewed = await _auth.refreshSession(session);
          await _sessionStore.save(renewed);
          _session = renewed;
          outcome = await _familySync.sync(renewed);
        } catch (_) {
          // Se conserva el error original, que ya explica qué hacer.
        }
      }

      if (outcome.success) {
        _familyGroupName = outcome.groupName ?? _familyGroupName;
        _lastFamilySyncUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _profilesList = await _profiles.loadAll();
      }
      return outcome;
    } finally {
      _syncingFamily = false;
      _notify();
    }
  }

  // --- Integrantes ----------------------------------------------------------

  /// Añade un integrante a mano como **excepción**.
  ///
  /// El flujo normal es el grupo familiar automático; esta vía existe solo para
  /// perfiles que no pertenecen al grupo (o para no quedarse sin nada si Steam
  /// no entrega el grupo).
  Future<OperationResult> addRescueProfile(String raw) async {
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
    }

    await _profiles.upsert(
      Profile(
        steamId64: steamId64,
        personaName: personaName,
        avatarUrl: avatarUrl,
        isFamilyMember: false,
        createdAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    _profilesList = await _profiles.loadAll();
    _notify();
    return OperationResult.ok('Perfil añadido.$note', steamId64: steamId64);
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
  ///
  /// Si el perfil vuelve a aparecer en el grupo familiar, la próxima
  /// sincronización lo traerá de nuevo: es el comportamiento esperado.
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
    _auth.dispose();
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
