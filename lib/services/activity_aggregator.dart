/// Agregación, filtrado y ordenación de la actividad.
///
/// Todas las funciones son puras y se prueban en
/// `test/core/activity_aggregator_test.dart`. La agregación se realiza
/// **siempre por AppID**: nunca por nombre de juego.
library;

import '../core/models.dart';

/// Criterios de ordenación disponibles en la interfaz.
enum GameSortOrder {
  /// Minutos recientes descendente (orden por defecto).
  recent,

  /// Nombre ascendente.
  name,

  /// Minutos acumulados descendente.
  forever,
}

/// Etiqueta en español de cada criterio de ordenación.
String describeSortOrder(GameSortOrder order) => switch (order) {
      GameSortOrder.recent => 'Tiempo reciente',
      GameSortOrder.name => 'Nombre',
      GameSortOrder.forever => 'Tiempo total',
    };

/// Aportación de un integrante a un juego agregado.
class MemberContribution {
  const MemberContribution({
    required this.steamId64,
    required this.displayName,
    required this.recentMinutes,
    required this.foreverMinutes,
  });

  final String steamId64;
  final String displayName;
  final int recentMinutes;

  /// `null` cuando Steam no comunicó el tiempo acumulado.
  final int? foreverMinutes;
}

/// Juego agregado a partir de uno o varios integrantes.
class AggregatedGame {
  const AggregatedGame({
    required this.appId,
    required this.name,
    required this.recentMinutes,
    required this.foreverMinutes,
    required this.contributions,
    required this.memberCount,
    required this.topSteamId64,
    required this.topDisplayName,
    required this.topRecentMinutes,
    required this.coverUrl,
  });

  final int appId;
  final String name;

  /// Suma de los minutos recientes de todos los integrantes.
  final int recentMinutes;

  /// Suma de los minutos acumulados, o `null` si a algún integrante le falta
  /// ese dato. Nunca se presenta un total parcial como si fuese completo.
  final int? foreverMinutes;

  /// Aportaciones individuales, ordenadas por minutos recientes descendente.
  final List<MemberContribution> contributions;

  /// Integrantes con actividad reciente en este juego.
  final int memberCount;

  /// Integrante con más minutos recientes en este juego (puede ser `null`).
  final String? topSteamId64;
  final String topDisplayName;
  final int topRecentMinutes;

  final String? coverUrl;

  /// `true` si el acumulado agregado está disponible para todos los integrantes.
  bool get hasCompleteForever => foreverMinutes != null;
}

/// Suma protegida de minutos: ignora valores negativos y satura ante desbordamiento.
int sumMinutes(Iterable<int?> values) {
  int total = 0;
  for (final int? v in values) {
    if (v == null || v <= 0) continue;
    final int next = total + v;
    if (next < total) return 0x7FFFFFFFFFFFFFFF;
    total = next;
  }
  return total;
}

/// `true` si todos los valores están presentes (ninguno es `null`).
bool allKnown(Iterable<int?> values) => values.every((int? v) => v != null);

/// Agrupa y suma los juegos de todas las actividades **por AppID**.
///
/// [include] permite excluir actividades concretas (por ejemplo, si el usuario
/// filtra por integrante en la pantalla General).
List<AggregatedGame> aggregateByAppId(
  List<ProfileActivity> activities, {
  bool Function(ProfileActivity activity)? include,
  Map<String, String> displayNames = const <String, String>{},
}) {
  // appId -> aportaciones
  final Map<int, List<MemberContribution>> byApp = <int, List<MemberContribution>>{};
  // appId -> nombre y portada conocidos
  final Map<int, String> names = <int, String>{};
  final Map<int, String?> covers = <int, String?>{};

  for (final ProfileActivity activity in activities) {
    if (include != null && !include(activity)) continue;
    // Solo se agregan actividades de las que Steam entregó una respuesta: un
    // fallo no debe contaminar los totales.
    if (!activity.status.isAnswered) continue;

    final String name = displayNames[activity.steamId64] ??
        activity.personaName ??
        'Perfil ${activity.steamId64}';

    for (final Game game in activity.games) {
      byApp.putIfAbsent(game.appId, () => <MemberContribution>[]).add(
            MemberContribution(
              steamId64: activity.steamId64,
              displayName: name,
              recentMinutes: game.playtime2Weeks,
              foreverMinutes: game.playtimeForever,
            ),
          );
      final String? gameName = game.name?.trim();
      if (gameName != null && gameName.isNotEmpty) {
        names.putIfAbsent(game.appId, () => gameName);
      }
      if (game.coverUrl != null && covers[game.appId] == null) {
        covers[game.appId] = game.coverUrl;
      }
    }
  }

  final List<AggregatedGame> result = <AggregatedGame>[];
  for (final MapEntry<int, List<MemberContribution>> entry in byApp.entries) {
    final List<MemberContribution> contributions = List<MemberContribution>.from(
      entry.value,
    )..sort((MemberContribution a, MemberContribution b) {
        final int byRecent = b.recentMinutes.compareTo(a.recentMinutes);
        if (byRecent != 0) return byRecent;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

    final int recent = sumMinutes(
      contributions.map((MemberContribution c) => c.recentMinutes),
    );
    final bool completeForever = allKnown(
      contributions.map((MemberContribution c) => c.foreverMinutes),
    );
    final int? forever = completeForever
        ? sumMinutes(contributions.map((MemberContribution c) => c.foreverMinutes))
        : null;

    final int activeMembers =
        contributions.where((MemberContribution c) => c.recentMinutes > 0).length;
    final MemberContribution top = contributions.first;

    result.add(
      AggregatedGame(
        appId: entry.key,
        name: names[entry.key] ?? 'AppID ${entry.key}',
        recentMinutes: recent,
        foreverMinutes: forever,
        contributions: contributions,
        memberCount: activeMembers > 0 ? activeMembers : contributions.length,
        topSteamId64: top.recentMinutes > 0 ? top.steamId64 : null,
        topDisplayName: top.displayName,
        topRecentMinutes: top.recentMinutes,
        coverUrl: covers[entry.key],
      ),
    );
  }

  result.sort(
    (AggregatedGame a, AggregatedGame b) => b.recentMinutes.compareTo(a.recentMinutes),
  );
  return result;
}

/// Ordena juegos según el criterio indicado.
///
/// Los valores desconocidos (`playtimeForever == null`) siempre quedan al final
/// cuando se ordena por tiempo acumulado.
List<Game> sortGames(List<Game> games, GameSortOrder order) {
  final List<Game> copy = List<Game>.from(games);
  switch (order) {
    case GameSortOrder.recent:
      copy.sort((Game a, Game b) {
        final int byRecent = b.playtime2Weeks.compareTo(a.playtime2Weeks);
        if (byRecent != 0) return byRecent;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    case GameSortOrder.name:
      copy.sort(
        (Game a, Game b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    case GameSortOrder.forever:
      copy.sort((Game a, Game b) {
        final int? fa = a.playtimeForever;
        final int? fb = b.playtimeForever;
        if (fa == null && fb == null) {
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        }
        if (fa == null) return 1;
        if (fb == null) return -1;
        final int byForever = fb.compareTo(fa);
        if (byForever != 0) return byForever;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
  }
  return copy;
}

/// Ordena los juegos agregados según el criterio indicado.
List<AggregatedGame> sortAggregatedGames(
  List<AggregatedGame> games,
  GameSortOrder order,
) {
  final List<AggregatedGame> copy = List<AggregatedGame>.from(games);
  switch (order) {
    case GameSortOrder.recent:
      copy.sort((AggregatedGame a, AggregatedGame b) {
        final int byRecent = b.recentMinutes.compareTo(a.recentMinutes);
        if (byRecent != 0) return byRecent;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    case GameSortOrder.name:
      copy.sort(
        (AggregatedGame a, AggregatedGame b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case GameSortOrder.forever:
      copy.sort((AggregatedGame a, AggregatedGame b) {
        final int? fa = a.foreverMinutes;
        final int? fb = b.foreverMinutes;
        if (fa == null && fb == null) {
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
        if (fa == null) return 1;
        if (fb == null) return -1;
        final int byForever = fb.compareTo(fa);
        if (byForever != 0) return byForever;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }
  return copy;
}

/// Indica si un juego supera el filtro de "ocultar actividad baja".
bool passesLowActivityFilter(Game game, {required bool hide, required int threshold}) {
  if (!hide) return true;
  return game.playtime2Weeks >= threshold;
}

/// Aplica búsqueda, filtro por integrante, filtro de actividad baja y
/// ordenación sobre las actividades mostradas en la pantalla Recientes.
///
/// - Si [query] coincide con el nombre de un integrante, se muestran todos sus
///   juegos.
/// - Si no, se filtran los juegos por nombre.
/// - Los integrantes sin juegos tras el filtrado se conservan (para poder
///   mostrar su estado), pero se ordenan al final.
List<ProfileActivity> filterAndSortActivities({
  required List<ProfileActivity> activities,
  Map<String, String> displayNames = const <String, String>{},
  String query = '',
  String? onlySteamId64,
  bool hideLowActivity = false,
  int lowActivityMinutes = 30,
  GameSortOrder order = GameSortOrder.recent,
}) {
  final String needle = query.trim().toLowerCase();

  final List<ProfileActivity> output = <ProfileActivity>[];
  for (final ProfileActivity activity in activities) {
    if (onlySteamId64 != null && activity.steamId64 != onlySteamId64) continue;

    final String name = displayNames[activity.steamId64] ??
        activity.personaName ??
        activity.steamId64;
    final bool memberMatches =
        needle.isNotEmpty && name.toLowerCase().contains(needle);

    List<Game> games = activity.games.where((Game game) {
      if (!passesLowActivityFilter(
        game,
        hide: hideLowActivity,
        threshold: lowActivityMinutes,
      )) {
        return false;
      }
      if (needle.isEmpty || memberMatches) return true;
      return game.label.toLowerCase().contains(needle);
    }).toList(growable: false);

    games = sortGames(games, order);
    output.add(activity.copyWith(games: games));
  }

  output.sort((ProfileActivity a, ProfileActivity b) {
    // Los perfiles sin juegos visibles se ordenan al final.
    final bool aEmpty = a.games.isEmpty;
    final bool bEmpty = b.games.isEmpty;
    if (aEmpty != bEmpty) return aEmpty ? 1 : -1;
    final int? ta = a.totalRecentMinutes;
    final int? tb = b.totalRecentMinutes;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });

  return output;
}

/// Suma de minutos recientes de un conjunto de actividades, o `null` si alguna
/// de las incluidas no dispone de respuesta válida.
int? totalRecentMinutesOf(List<ProfileActivity> activities) {
  if (activities.isEmpty) return 0;
  if (activities.any((ProfileActivity a) => a.totalRecentMinutes == null)) return null;
  return sumMinutes(activities.map((ProfileActivity a) => a.totalRecentMinutes));
}

/// Suma de minutos acumulados, o `null` si falta algún dato.
int? totalForeverMinutesOf(List<ProfileActivity> activities) {
  if (activities.isEmpty) return 0;
  if (activities.any((ProfileActivity a) => a.totalForeverMinutes == null)) return null;
  return sumMinutes(activities.map((ProfileActivity a) => a.totalForeverMinutes));
}

/// Número de juegos distintos (por AppID) entre todas las actividades.
int distinctGameCount(List<ProfileActivity> activities) {
  final Set<int> ids = <int>{};
  for (final ProfileActivity activity in activities) {
    if (!activity.status.isAnswered) continue;
    for (final Game game in activity.games) {
      ids.add(game.appId);
    }
  }
  return ids.length;
}
