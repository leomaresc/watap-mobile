/// Parseo defensivo de las respuestas JSON de la Steam Web API.
///
/// Reglas generales:
/// - Nunca se asume que un campo existe o tiene el tipo esperado.
/// - Un JSON inválido lanza [SteamApiException] con
///   `SteamApiErrorKind.malformedResponse`.
/// - Los tiempos negativos se saturan a cero para evitar totales imposibles.
/// - Un dato ausente se conserva como desconocido (`null`), nunca como cero
///   silencioso.
///
/// Se prueban en `test/data/steam_json_parsers_test.dart` con respuestas
/// ficticias; la suite no realiza llamadas reales a Steam.
library;

import 'dart:convert';

import '../../core/models.dart';
import 'steam_api_errors.dart';
import 'steam_api_urls.dart';

/// Resultado del parseo de `GetRecentlyPlayedGames`.
class RecentlyPlayedParseResult {
  const RecentlyPlayedParseResult({
    required this.responsePresent,
    required this.totalCount,
    required this.games,
  });

  /// `false` cuando Steam responde `{"response":{}}`.
  ///
  /// Es exactamente el caso de un perfil privado o de datos no disponibles:
  /// **no** debe interpretarse como "cero juegos recientes".
  final bool responsePresent;

  /// Campo `total_count`, cuando Steam lo incluye. Su valor `0` sí expresa
  /// una respuesta válida sin juegos recientes.
  final int? totalCount;

  final List<Game> games;

  /// `true` cuando Steam entregó datos utilizables.
  bool get isUsable => responsePresent;

  /// `true` cuando hay juegos que mostrar.
  bool get hasGames => games.isNotEmpty;
}

/// Decodifica el cuerpo de una respuesta como objeto JSON.
///
/// Lanza [SteamApiException] si el cuerpo está vacío, no es JSON o no es un
/// objeto.
Object? _decodeJsonObject(String body, String endpoint) {
  final String trimmed = body.trim();
  if (trimmed.isEmpty) {
    throw SteamApiException(
      kind: SteamApiErrorKind.malformedResponse,
      messageEs: 'Steam devolvió una respuesta vacía.',
      endpoint: endpoint,
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed) as Object?;
  } on FormatException {
    throw SteamApiException(
      kind: SteamApiErrorKind.malformedResponse,
      messageEs: 'Steam devolvió un JSON que no se pudo interpretar.',
      endpoint: endpoint,
      technicalDetail: 'FormatException al decodificar JSON',
    );
  }
  if (decoded is! Map<String, Object?>) {
    // `jsonDecode` produce Map<String, dynamic>; se normaliza aquí.
    if (decoded is Map) {
      return decoded.map<String, Object?>(
        (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
      );
    }
    throw SteamApiException(
      kind: SteamApiErrorKind.malformedResponse,
      messageEs: 'Steam devolvió un JSON con una estructura inesperada.',
      endpoint: endpoint,
      technicalDetail: 'Se esperaba un objeto JSON, se recibió ${decoded.runtimeType}',
    );
  }
  return decoded;
}

Map<String, Object?> _asStringKeyMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map<String, Object?>(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );
  }
  return const <String, Object?>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const <Object?>[];
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _asNonEmptyString(Object? value) {
  if (value is String) {
    final String t = value.trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}

/// Minutos: satura negativos a cero para no producir totales imposibles.
int _minutes(Object? value) {
  final int raw = _asInt(value) ?? 0;
  return raw < 0 ? 0 : raw;
}

/// Interpreta `IPlayerService/GetRecentlyPlayedGames/v1`.
RecentlyPlayedParseResult parseRecentlyPlayedGames(String body) {
  final Object? decoded = _decodeJsonObject(body, SteamApiUrls.recentlyPlayed('').path);
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Object? responseRaw = root['response'];
  final Map<String, Object?> response = _asStringKeyMap(responseRaw);

  if (responseRaw is! Map || response.isEmpty) {
    // Perfil privado o sin datos disponibles.
    return const RecentlyPlayedParseResult(
      responsePresent: false,
      totalCount: null,
      games: <Game>[],
    );
  }

  final int? totalCount = _asInt(response['total_count']);
  final List<Game> games = <Game>[];
  for (final Object? item in _asList(response['games'])) {
    final Map<String, Object?> map = _asStringKeyMap(item);
    final int? appId = _asInt(map['appid']);
    if (appId == null || appId <= 0) continue;

    // Steam marca con `playtime_forever: 0` cuando el dato no está disponible
    // para ese juego concreto; se conserva como desconocido salvo que
    // `playtime_2weeks` indique actividad real.
    final Object? foreverRaw = map['playtime_forever'];
    final int? forever = foreverRaw == null ? null : _minutes(foreverRaw);

    final String? iconHash = _asNonEmptyString(map['img_icon_url']);
    games.add(
      Game(
        appId: appId,
        name: _asNonEmptyString(map['name']),
        playtime2Weeks: _minutes(map['playtime_2weeks']),
        playtimeForever: forever,
        coverUrl: SteamApiUrls.gameCover(appId).toString(),
        iconUrl: iconHash == null
            ? null
            : SteamApiUrls.gameIcon(appId, iconHash).toString(),
      ),
    );
  }

  games.sort((Game a, Game b) {
    final int byRecent = b.playtime2Weeks.compareTo(a.playtime2Weeks);
    if (byRecent != 0) return byRecent;
    return b.appId.compareTo(a.appId);
  });

  return RecentlyPlayedParseResult(
    responsePresent: true,
    totalCount: totalCount,
    games: games,
  );
}

/// Interpreta `IFamilyGroupsService/GetFamilyGroupForUser/v1`.
///
/// Devuelve el identificador del grupo familiar de la cuenta autenticada. Si la
/// cuenta no pertenece a ningún grupo, Steam responde `{"response":{}}` y aquí
/// se devuelve `familyGroupId == null`.
FamilyGroupForUser parseFamilyGroupForUser(String body) {
  final Object? decoded = _decodeJsonObject(
    body,
    '/IFamilyGroupsService/GetFamilyGroupForUser/v1/',
  );
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);
  return FamilyGroupForUser(
    familyGroupId: _asNonEmptyString(response['family_groupid']),
  );
}

/// Interpreta `IFamilyGroupsService/GetFamilyGroup/v1`.
///
/// Devuelve el nombre del grupo y su lista de integrantes. Los identificadores
/// mal formados se descartan y los duplicados se eliminan; si al final no queda
/// ningún integrante, se considera una respuesta no utilizable.
FamilyGroup parseFamilyGroup(
  String body, {
  required String familyGroupId,
}) {
  final Object? decoded = _decodeJsonObject(
    body,
    '/IFamilyGroupsService/GetFamilyGroup/v1/',
  );
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final List<FamilyGroupMember> members = <FamilyGroupMember>[];
  final Set<String> seen = <String>{};
  for (final Object? item in _asList(response['members'])) {
    final Map<String, Object?> map = _asStringKeyMap(item);
    final String? id = _asNonEmptyString(map['steamid']);
    if (id == null || id.length != 17 || !seen.add(id)) continue;
    members.add(
      FamilyGroupMember(
        steamId64: id,
        role: _asInt(map['role']),
        timeJoinedUnix: _asInt(map['time_joined']),
      ),
    );
  }

  return FamilyGroup(
    familyGroupId: familyGroupId,
    name: _asNonEmptyString(response['name']),
    members: members,
    freeSpots: _asInt(response['free_spots']),
  );
}