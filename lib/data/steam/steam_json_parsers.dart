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

import '../../core/constants.dart';
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

/// Interpreta `ISteamUser/GetPlayerSummaries/v2`.
///
/// Devuelve únicamente los perfiles que Steam ha reconocido. Una lista vacía
/// significa "Steam no reconoce esos SteamID64", no un error de formato.
List<SteamPlayerSummary> parsePlayerSummaries(String body) {
  final Object? decoded =
      _decodeJsonObject(body, SteamApiUrls.playerSummaries(const <String>[]).path);
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final List<SteamPlayerSummary> result = <SteamPlayerSummary>[];
  for (final Object? item in _asList(response['players'])) {
    final Map<String, Object?> map = _asStringKeyMap(item);
    final String? id = _asNonEmptyString(map['steamid']);
    if (id == null || id.length != 17) continue;
    result.add(
      SteamPlayerSummary(
        steamId64: id,
        personaName: _asNonEmptyString(map['personaname']),
        avatarUrl: _asNonEmptyString(map['avatarfull']) ??
            _asNonEmptyString(map['avatarmedium']) ??
            _asNonEmptyString(map['avatar']),
        profileUrl: _asNonEmptyString(map['profileurl']),
        communityVisibilityState: _asInt(map['communityvisibilitystate']),
        personaState: _asInt(map['personastate']),
      ),
    );
  }
  return result;
}

/// Interpreta `ISteamUser/ResolveVanityURL/v1`.
///
/// `success == 1` indica resolución correcta; `success == 42` es el código
/// documentado por Steam para "no se encontró ningún perfil con ese nombre".
VanityResolution parseVanityResolution(String body) {
  final Object? decoded =
      _decodeJsonObject(body, SteamApiUrls.resolveVanityUrl('').path);
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final int? success = _asInt(response['success']);
  final String? steamId = _asNonEmptyString(response['steamid']);

  if (success == 1 && steamId != null && steamId.length == 17) {
    return VanityResolution(success: true, steamId64: steamId);
  }

  final String messageEs = switch (success) {
    42 => 'No existe ningún perfil de Steam con ese nombre personalizado.',
    2 => 'El nombre personalizado indicado no existe.',
    _ => 'Steam no ha podido resolver ese nombre personalizado.',
  };
  return VanityResolution(success: false, messageEs: messageEs);
}

/// Interpreta `IFamilyGroupsService/GetFamilyGroupForUser/v1`.
///
/// Solo necesita el `access_token` de la sesión de Steam. Cuando la cuenta no
/// pertenece a ningún grupo familiar, Steam responde con
/// `is_not_member_of_any_group: true` y sin `family_groupid`.
FamilyGroupForUser parseFamilyGroupForUser(String body) {
  final Object? decoded = _decodeJsonObject(
    body,
    AppConstants.steamFamilyGroupForUserPath,
  );
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final String? groupId = _asNonEmptyString(response['family_groupid']);
  final bool notMember = response['is_not_member_of_any_group'] == true;

  if (groupId == null && !notMember) {
    // Steam devolvió una respuesta que no permite decidir. Se trata como "sin
    // grupo" para no inventar integrantes, pero se conserva el detalle.
    return const FamilyGroupForUser.none();
  }
  return FamilyGroupForUser(
    familyGroupId: groupId,
    isNotMemberOfAnyGroup: notMember || groupId == null,
  );
}

/// Interpreta `IFamilyGroupsService/GetFamilyGroup/v1`.
///
/// [familyGroupId] se usa solo como respaldo cuando la respuesta no lo incluye,
/// porque el endpoint no siempre lo repite.
FamilyGroup parseFamilyGroup(
  String body, {
  required String familyGroupId,
}) {
  final Object? decoded = _decodeJsonObject(
    body,
    AppConstants.steamFamilyGroupPath,
  );
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final List<FamilyGroupMember> members = <FamilyGroupMember>[];
  final Set<String> seen = <String>{};
  for (final Object? item in _asList(response['members'])) {
    final Map<String, Object?> map = _asStringKeyMap(item);
    final String? id = _asNonEmptyString(map['steamid']);
    if (id == null || id.length != 17) continue;
    if (!seen.add(id)) continue;
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

// --- Autenticación (flujo interno del cliente de Steam) ---------------------

/// Respuesta de `IAuthenticationService/GetPasswordRSAPublicKey/v1`.
class PasswordRsaKeyParse {
  const PasswordRsaKeyParse({
    required this.modulusHex,
    required this.exponentHex,
    required this.timestamp,
  });

  final String modulusHex;
  final String exponentHex;
  final int timestamp;
}

/// Interpreta `GetPasswordRSAPublicKey`.
PasswordRsaKeyParse parsePasswordRsaPublicKey(String body) {
  final Object? decoded = _decodeJsonObject(body, 'GetPasswordRSAPublicKey');
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final String? modulus = _asNonEmptyString(response['publickey_mod']);
  final String? exponent = _asNonEmptyString(response['publickey_exp']);
  final int? timestamp = _asInt(response['timestamp']);
  if (modulus == null || exponent == null || timestamp == null) {
    throw const SteamApiException(
      kind: SteamApiErrorKind.malformedResponse,
      messageEs: 'Steam no entregó la clave pública necesaria para iniciar '
          'sesión.',
      endpoint: 'GetPasswordRSAPublicKey',
    );
  }
  return PasswordRsaKeyParse(
    modulusHex: modulus,
    exponentHex: exponent,
    timestamp: timestamp,
  );
}

/// Respuesta de `BeginAuthSessionViaCredentials`.
class BeginAuthSessionParse {
  const BeginAuthSessionParse({
    required this.clientId,
    required this.requestId,
    this.steamId64,
    required this.intervalSeconds,
    this.confirmationTypes = const <int>[],
    this.confirmationMessage,
  });

  final String clientId;
  final String requestId;
  final String? steamId64;
  final int intervalSeconds;

  /// Tipos de confirmación admitidos (2 = correo, 3 = código de dispositivo).
  final List<int> confirmationTypes;

  /// Mensaje que Steam asocia a la confirmación (por ejemplo, el correo al que
  /// envió el código).
  final String? confirmationMessage;

  /// `true` cuando hace falta que el usuario escriba un código.
  bool get needsCode => confirmationTypes.contains(2) ||
      confirmationTypes.contains(3);
}

/// Interpreta `BeginAuthSessionViaCredentials`.
BeginAuthSessionParse parseBeginAuthSession(String body) {
  final Object? decoded = _decodeJsonObject(body, 'BeginAuthSessionViaCredentials');
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  final String? clientId = _asNonEmptyString(
    response['client_id'] ?? response['clientid'],
  );
  final String? requestId = _asNonEmptyString(
    response['request_id'] ?? response['requestid'],
  );
  if (clientId == null || requestId == null) {
    throw const SteamApiException(
      kind: SteamApiErrorKind.malformedResponse,
      messageEs: 'Steam no inició la sesión de acceso correctamente.',
      endpoint: 'BeginAuthSessionViaCredentials',
    );
  }

  final List<int> types = <int>[];
  String? message;
  for (final Object? item in _asList(response['allowed_confirmations'])) {
    final Map<String, Object?> map = _asStringKeyMap(item);
    final int? type = _asInt(map['confirmation_type']);
    if (type != null) types.add(type);
    message ??= _asNonEmptyString(map['associated_message']);
  }

  final int interval = _asInt(response['interval']) ?? 5;
  return BeginAuthSessionParse(
    clientId: clientId,
    requestId: requestId,
    steamId64: _asNonEmptyString(response['steamid']),
    intervalSeconds: interval <= 0 ? 5 : interval,
    confirmationTypes: types,
    confirmationMessage: message,
  );
}

/// Respuesta de `PollAuthSessionStatus`.
class PollAuthSessionParse {
  const PollAuthSessionParse({
    this.accessToken,
    this.refreshToken,
    this.accountName,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? accountName;

  /// `true` cuando Steam ya entregó la sesión.
  bool get isComplete =>
      (accessToken ?? '').isNotEmpty && (refreshToken ?? '').isNotEmpty;
}

/// Interpreta `PollAuthSessionStatus`. Un resultado incompleto significa que
/// Steam todavía no ha confirmado el acceso.
PollAuthSessionParse parsePollAuthSession(String body) {
  final Object? decoded = _decodeJsonObject(body, 'PollAuthSessionStatus');
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);

  return PollAuthSessionParse(
    accessToken: _asNonEmptyString(response['access_token']),
    refreshToken: _asNonEmptyString(response['refresh_token']),
    accountName: _asNonEmptyString(response['account_name']),
  );
}

/// Interpreta `IAuthenticationService/GenerateAccessTokenForApp/v1`.
String? parseGenerateAccessToken(String body) {
  final Object? decoded = _decodeJsonObject(body, 'GenerateAccessTokenForApp');
  final Map<String, Object?> root = _asStringKeyMap(decoded);
  final Map<String, Object?> response = _asStringKeyMap(root['response']);
  return _asNonEmptyString(response['access_token']);
}
