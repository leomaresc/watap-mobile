/// Coordinador de actualizaciones.
///
/// Se encarga de:
/// - Consultar perfiles (uno o todos) sin bloquear la interfaz.
/// - Limitar la concurrencia de las solicitudes de red.
/// - Evitar actualizaciones duplicadas del mismo perfil.
/// - Traducir los errores técnicos a estados de la interfaz.
/// - Conservar los datos anteriores cuando una consulta falla.
/// - Descartar respuestas tardías que intentarían sobrescribir un estado más
///   reciente, y cancelar de forma segura al cambiar de ciclo de vida.
///
/// No crea procesos en segundo plano ni temporizadores periódicos: todo se
/// ejecuta como operaciones asíncronas de Dart mientras la aplicación está
/// activa.
library;

import 'dart:async';
import 'dart:collection';

import '../core/models.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/profiles_repository.dart';
import '../data/steam/steam_api_client.dart';
import '../data/steam/steam_api_errors.dart';
import '../data/steam/steam_json_parsers.dart';

/// Coordinador de actualizaciones de actividad.
class RefreshCoordinator {
  RefreshCoordinator({
    required SteamApiClient api,
    required ActivityRepository activities,
    required ProfilesRepository profiles,
    int maxConcurrent = 3,
  })  : _api = api,
        _activities = activities,
        _profiles = profiles,
        _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  final SteamApiClient _api;
  final ActivityRepository _activities;
  final ProfilesRepository _profiles;
  final int _maxConcurrent;

  /// Perfiles cuya actualización está en curso.
  final Set<String> _inProgress = <String>{};

  /// Generación de la última actualización lanzada para cada perfil.
  ///
  /// Permite descartar una respuesta antigua que llegue después de otra más
  /// reciente.
  final Map<String, int> _generation = <String, int>{};

  bool _disposed = false;

  /// `true` si hay al menos una actualización en curso.
  bool get isBusy => _inProgress.isNotEmpty;

  /// `true` si el perfil indicado se está actualizando.
  bool isRefreshing(String steamId64) => _inProgress.contains(steamId64);

  /// SteamID64 con actualización en curso (copia defensiva).
  Set<String> get refreshingProfiles => Set<String>.unmodifiable(_inProgress);

  /// Actualiza un perfil y devuelve la actividad que debe mostrarse.
  ///
  /// Nunca lanza: los fallos se traducen a [FetchStatus]. Si ya había datos,
  /// se conservan y se marcan como procedentes de la caché.
  Future<ProfileActivity> refreshProfile(
    Profile profile, {
    ProfileActivity? previous,
  }) async {
    if (_disposed) {
      return previous ??
          ProfileActivity(
            steamId64: profile.steamId64,
            personaName: profile.personaName,
            avatarUrl: profile.avatarUrl,
            status: FetchStatus.notFetched,
          );
    }

    if (_inProgress.contains(profile.steamId64)) {
      // Ya hay una actualización en curso: se devuelve lo que hubiera para no
      // duplicar solicitudes.
      if (previous != null) return previous;
      final ProfileActivity? current = await _activities.loadOne(profile.steamId64);
      return current ??
          ProfileActivity(
            steamId64: profile.steamId64,
            personaName: profile.personaName,
            status: FetchStatus.notFetched,
          );
    }

    final int generation = _bumpGeneration(profile.steamId64);
    _inProgress.add(profile.steamId64);
    try {
      final ProfileActivity fresh = await _fetch(profile, previous: previous);

      if (!_isCurrent(profile.steamId64, generation)) {
        // Una consulta posterior ya ha sustituido a esta: no se persiste para
        // no sobrescribir datos más recientes.
        final ProfileActivity? current =
            await _activities.loadOne(profile.steamId64);
        return current ?? fresh;
      }

      try {
        return await _activities.saveResult(fresh, previous: previous);
      } catch (_) {
        // Si el almacenamiento local falla (por ejemplo, por una restricción de
        // integridad), se devuelve el resultado sin persistir en lugar de
        // propagar el error: la interfaz debe seguir funcionando.
        return fresh.copyWith(
          fetchedAtUnix: fresh.fetchedAtUnix ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
      }
    } finally {
      _inProgress.remove(profile.steamId64);
    }
  }

  /// Actualiza varios perfiles emitiendo resultados **a medida que llegan**.
  ///
  /// El flujo puede cancelarse en cualquier momento (por ejemplo, al cerrar la
  /// pantalla): los resultados pendientes se descartan.
  Stream<ProfileActivity> refreshAll(
    List<Profile> profiles, {
    Map<String, ProfileActivity> cached = const <String, ProfileActivity>{},
  }) {
    final StreamController<ProfileActivity> controller =
        StreamController<ProfileActivity>();
    final Queue<Profile> queue = Queue<Profile>.of(profiles);
    bool cancelled = false;

    Future<void> worker() async {
      while (queue.isNotEmpty && !cancelled && !_disposed) {
        final Profile profile = queue.removeFirst();
        try {
          final ProfileActivity activity = await refreshProfile(
            profile,
            previous: cached[profile.steamId64],
          );
          if (!cancelled && !controller.isClosed) controller.add(activity);
        } catch (e) {
          // `refreshProfile` no debería lanzar, pero si ocurre algo
          // inesperado se emite un estado de error en lugar de romper el flujo.
          if (!cancelled && !controller.isClosed) {
            controller.add(
              (cached[profile.steamId64] ??
                      ProfileActivity(steamId64: profile.steamId64))
                  .copyWith(
                status: FetchStatus.networkError,
                statusMessage: 'Error inesperado al actualizar el perfil.',
                fromCache: (cached[profile.steamId64]?.games ?? const <Game>[]).isNotEmpty,
                isStale: true,
              ),
            );
          }
        }
      }
    }

    controller.onListen = () {
      final int workers =
          queue.length < _maxConcurrent ? queue.length : _maxConcurrent;
      if (workers == 0) {
        unawaited(controller.close());
        return;
      }
      unawaited(
        Future.wait<void>(
          List<Future<void>>.generate(workers, (_) => worker()),
        ).then((_) {
          if (!controller.isClosed) unawaited(controller.close());
        }),
      );
    };

    controller.onCancel = () {
      cancelled = true;
      unawaited(controller.close());
    };

    return controller.stream;
  }

  /// Marca el coordinador como descartado y vacía el estado interno.
  void dispose() {
    _disposed = true;
    _inProgress.clear();
    _generation.clear();
  }

  // -------------------------------------------------------------------------

  int _bumpGeneration(String steamId64) {
    final int next = (_generation[steamId64] ?? 0) + 1;
    _generation[steamId64] = next;
    return next;
  }

  bool _isCurrent(String steamId64, int generation) =>
      _generation[steamId64] == generation;

  /// Realiza la consulta completa de un perfil real.
  Future<ProfileActivity> _fetch(
    Profile profile, {
    ProfileActivity? previous,
  }) async {
    final String id = profile.steamId64;

    if (!_api.hasApiKey) {
      return ProfileActivity(
        steamId64: id,
        personaName: profile.personaName,
        avatarUrl: profile.avatarUrl,
        status: FetchStatus.incompleteConfiguration,
        statusMessage: 'Configura tu clave de Steam Web API en Ajustes para '
            'consultar perfiles reales.',
      );
    }

    try {
      // 1) Datos públicos del perfil (nombre, avatar, visibilidad).
      final List<SteamPlayerSummary> summaries =
          await _api.fetchPlayerSummaries(<String>[id]);
      final SteamPlayerSummary? summary = _firstOrNull(summaries, id);

      if (summary == null) {
        return ProfileActivity(
          steamId64: id,
          personaName: profile.personaName,
          avatarUrl: profile.avatarUrl,
          status: FetchStatus.invalidProfile,
          statusMessage: 'Steam no reconoce el SteamID64 $id. '
              'Comprueba que sea correcto y que la cuenta exista.',
        );
      }

      // Se actualiza el nombre y el avatar almacenados (dato público).
      await _profiles.applySummary(summary);

      // 2) Si el perfil no es público, Steam no entregará los detalles de
      //    juego. Se informa de la causa concreta de forma proactiva.
      final int? visibility = summary.communityVisibilityState;
      if (visibility != null && visibility != 3) {
        return ProfileActivity(
          steamId64: id,
          personaName: summary.personaName ?? profile.personaName,
          avatarUrl: summary.avatarUrl ?? profile.avatarUrl,
          status: FetchStatus.privateOrUnavailable,
          statusMessage: _visibilityMessage(visibility),
        );
      }

      // 3) Juegos recientes.
      final RecentlyPlayedParseResult recent =
          await _api.fetchRecentlyPlayedGames(id);

      if (!recent.isUsable) {
        // Respuesta `{"response":{}}`: Steam no ha entregado datos. No se debe
        // interpretar como "cero juegos".
        return ProfileActivity(
          steamId64: id,
          personaName: summary.personaName ?? profile.personaName,
          avatarUrl: summary.avatarUrl ?? profile.avatarUrl,
          status: FetchStatus.privateOrUnavailable,
          statusMessage: 'Steam no ha entregado los juegos recientes. Suele '
              'deberse a que los "Detalles del juego" del perfil son privados.',
        );
      }

      if (recent.games.isEmpty) {
        return ProfileActivity(
          steamId64: id,
          personaName: summary.personaName ?? profile.personaName,
          avatarUrl: summary.avatarUrl ?? profile.avatarUrl,
          status: FetchStatus.noRecentGames,
          statusMessage: 'Steam comunica cero juegos en las últimas dos '
              'semanas. Esto no significa que el perfil no haya jugado nunca.',
        );
      }

      return ProfileActivity(
        steamId64: id,
        personaName: summary.personaName ?? profile.personaName,
        avatarUrl: summary.avatarUrl ?? profile.avatarUrl,
        games: recent.games,
        status: FetchStatus.ok,
        statusMessage: recent.totalCount == null
            ? null
            : 'Steam comunica ${recent.totalCount} juegos recientes.',
      );
    } on SteamApiException catch (e) {
      return ProfileActivity(
        steamId64: id,
        personaName: profile.personaName,
        avatarUrl: profile.avatarUrl,
        status: fetchStatusForSteamError(e.kind),
        statusMessage: e.messageEs,
      );
    } catch (e) {
      // Salvaguarda: ningún fallo inesperado debe tumbar la actualización.
      return ProfileActivity(
        steamId64: id,
        personaName: profile.personaName,
        avatarUrl: profile.avatarUrl,
        status: FetchStatus.networkError,
        statusMessage: 'No se pudo completar la consulta: ${e.runtimeType}.',
      );
    }
  }

  static SteamPlayerSummary? _firstOrNull(
    List<SteamPlayerSummary> summaries,
    String steamId64,
  ) {
    for (final SteamPlayerSummary summary in summaries) {
      if (summary.steamId64 == steamId64) return summary;
    }
    return null;
  }

  static String _visibilityMessage(int visibility) => switch (visibility) {
        1 => 'El perfil es privado en Steam, por lo que la API no entrega sus '
            'juegos recientes. Puedes cambiar esto en la configuración de '
            'privacidad de Steam.',
        2 => 'El perfil solo es visible para amigos. La Steam Web API no '
            'entregará los detalles de juego.',
        _ => 'El perfil no tiene los "Detalles del juego" públicos.',
      };
}
