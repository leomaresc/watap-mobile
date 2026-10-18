/// Modelos de dominio de WATAP Mobile.
///
/// Son clases Dart puras: no conocen la interfaz, ni HTTP, ni SQLite. Las
/// conversiones a/desde mapas se limitan a `Map<String, Object?>`, sin
/// depender de `sqflite` ni de `json`.
library;

import 'constants.dart';

/// Nivel de actividad calculado a partir de los minutos recientes.
///
/// Es una *clasificación histórica*, nunca una medición en tiempo real.
enum ActivityLevel {
  /// Cero minutos recientes comunicados por la API.
  none,

  /// Por debajo del umbral moderado.
  low,

  /// Desde el umbral moderado hasta antes del umbral alto.
  moderate,

  /// Igual o superior al umbral alto.
  high,
}

/// Estado del resultado de una consulta a Steam.
enum FetchStatus {
  /// Todavía no se ha consultado el perfil.
  notFetched,

  /// Consulta válida con juegos recientes.
  ok,

  /// Respuesta válida que indica cero juegos recientes.
  noRecentGames,

  /// Datos inaccesibles, restringidos por privacidad o insuficientes.
  privateOrUnavailable,

  /// No fue posible completar la consulta por un problema de red o tiempo de espera.
  networkError,

  /// La respuesta permite identificar realmente una clave inválida.
  invalidApiKey,

  /// La entrada del perfil es incorrecta o Steam confirma que no puede resolverse.
  invalidProfile,

  /// Se alcanzó el límite de solicitudes.
  rateLimited,

  /// La respuesta llegó con formato inesperado o JSON inválido.
  malformedResponse,

  /// Falta configuración necesaria (por ejemplo, la clave de API).
  incompleteConfiguration;

  /// `true` si el estado representa una respuesta que Steam sí ha entregado.
  bool get isAnswered =>
      this == FetchStatus.ok || this == FetchStatus.noRecentGames;

  /// `true` si Steam entregó una respuesta con juegos.
  bool get hasGames => this == FetchStatus.ok;

  /// `true` si el estado final es un fallo.
  bool get isFailure => !isAnswered;
}

/// Resumen de un perfil de Steam tal como lo devuelve `GetPlayerSummaries`.
///
/// No implica autenticación: es información pública del perfil.
class SteamPlayerSummary {
  const SteamPlayerSummary({
    required this.steamId64,
    this.personaName,
    this.avatarUrl,
    this.profileUrl,
    this.communityVisibilityState,
    this.personaState,
  });

  final String steamId64;
  final String? personaName;
  final String? avatarUrl;
  final String? profileUrl;

  /// 1 = privado, 2 = solo amigos, 3 = público (según el campo
  /// `communityvisibilitystate` de Steam).
  final int? communityVisibilityState;

  /// 0 = desconectado, 1..6 = estados concretos. Es información pública del
  /// perfil y **no** se usa para afirmar que alguien está jugando ahora.
  final int? personaState;

  /// `true` cuando Steam confirma que el perfil es público.
  bool get isPublicProfile => communityVisibilityState == 3;

  @override
  String toString() => 'SteamPlayerSummary($steamId64, $personaName)';
}

/// Resultado de resolver un nombre personalizado de Steam.
class VanityResolution {
  const VanityResolution({required this.success, this.steamId64, this.messageEs});

  final bool success;
  final String? steamId64;
  final String? messageEs;
}

/// Sesión de Steam obtenida al iniciar sesión.
///
/// Los tokens se guardan **exclusivamente** en el almacenamiento seguro del
/// dispositivo (nunca en SQLite ni en JSON en claro). El `accessToken` es el que
/// permite consultar el grupo familiar.
class SteamSession {
  const SteamSession({
    required this.steamId64,
    required this.accessToken,
    required this.refreshToken,
    this.accountName,
    required this.savedAtUnix,
  });

  /// Cuenta autenticada. Es también "mi perfil" dentro de la aplicación.
  final String steamId64;

  final String accessToken;
  final String refreshToken;

  /// Nombre de la cuenta usado al iniciar sesión (dato público del propio
  /// usuario; se guarda para mostrarlo en Ajustes).
  final String? accountName;

  final int savedAtUnix;

  SteamSession copyWith({
    String? steamId64,
    String? accessToken,
    String? refreshToken,
    String? accountName,
    int? savedAtUnix,
  }) {
    return SteamSession(
      steamId64: steamId64 ?? this.steamId64,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accountName: accountName ?? this.accountName,
      savedAtUnix: savedAtUnix ?? this.savedAtUnix,
    );
  }

  @override
  String toString() => 'SteamSession($steamId64)';
}

/// Respuesta de `IFamilyGroupsService/GetFamilyGroupForUser`.
class FamilyGroupForUser {
  const FamilyGroupForUser({
    required this.familyGroupId,
    required this.isNotMemberOfAnyGroup,
  });

  const FamilyGroupForUser.none()
      : familyGroupId = null,
        isNotMemberOfAnyGroup = true;

  final String? familyGroupId;
  final bool isNotMemberOfAnyGroup;

  /// `true` cuando la cuenta pertenece a algún grupo familiar.
  bool get hasGroup => !isNotMemberOfAnyGroup && (familyGroupId ?? '').isNotEmpty;
}

/// Un integrante del grupo familiar.
class FamilyGroupMember {
  const FamilyGroupMember({
    required this.steamId64,
    this.role,
    this.timeJoinedUnix,
  });

  final String steamId64;

  /// Rol dentro del grupo (por ejemplo, 0 = adulto, 1 = menor). Puede faltar.
  final int? role;

  final int? timeJoinedUnix;
}

/// Respuesta de `IFamilyGroupsService/GetFamilyGroup`.
class FamilyGroup {
  const FamilyGroup({
    required this.familyGroupId,
    this.name,
    this.members = const <FamilyGroupMember>[],
    this.freeSpots,
  });

  final String familyGroupId;
  final String? name;
  final List<FamilyGroupMember> members;
  final int? freeSpots;

  List<String> get memberSteamIds =>
      members.map((FamilyGroupMember m) => m.steamId64).toList(growable: false);

  @override
  String toString() =>
      'FamilyGroup($familyGroupId, ${members.length} integrantes)';
}

/// Perfil supervisado por la aplicación.
///
/// Los integrantes se obtienen automáticamente del grupo familiar de Steam. La
/// vía manual queda solo como rescate para casos excepcionales.
class Profile {
  const Profile({
    required this.steamId64,
    this.personaName,
    this.avatarUrl,
    this.alias,
    this.isOwnProfile = false,
    this.isFamilyMember = false,
    required this.createdAtUnix,
  });

  final String steamId64;

  /// Nombre público devuelto por Steam. Puede cambiar en cualquier momento.
  final String? personaName;

  final String? avatarUrl;

  /// Nombre local opcional definido por el usuario para distinguir personas.
  final String? alias;

  /// `true` para la cuenta con la que el usuario ha iniciado sesión en Steam.
  final bool isOwnProfile;

  /// `true` si el perfil se ha obtenido del grupo familiar de Steam.
  final bool isFamilyMember;

  final int createdAtUnix;

  /// Nombre a mostrar: alias local, si existe; si no, nombre público.
  String get displayName {
    final String? a = alias?.trim();
    if (a != null && a.isNotEmpty) return a;
    final String? p = personaName?.trim();
    if (p != null && p.isNotEmpty) return p;
    return 'Perfil $steamId64';
  }

  Profile copyWith({
    String? steamId64,
    String? personaName,
    String? avatarUrl,
    String? alias,
    bool clearAlias = false,
    bool? isOwnProfile,
    bool? isFamilyMember,
    int? createdAtUnix,
  }) {
    return Profile(
      steamId64: steamId64 ?? this.steamId64,
      personaName: personaName ?? this.personaName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      alias: clearAlias ? null : (alias ?? this.alias),
      isOwnProfile: isOwnProfile ?? this.isOwnProfile,
      isFamilyMember: isFamilyMember ?? this.isFamilyMember,
      createdAtUnix: createdAtUnix ?? this.createdAtUnix,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'steam_id64': steamId64,
        'persona_name': personaName,
        'avatar_url': avatarUrl,
        'alias': alias,
        'is_own_profile': isOwnProfile ? 1 : 0,
        'is_family_member': isFamilyMember ? 1 : 0,
        'created_at': createdAtUnix,
      };

  static Profile fromMap(Map<String, Object?> map) => Profile(
        steamId64: (map['steam_id64'] as String?) ?? '',
        personaName: map['persona_name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        alias: map['alias'] as String?,
        isOwnProfile: _asBool(map['is_own_profile']),
        isFamilyMember: _asBool(map['is_family_member']),
        createdAtUnix: _asInt(map['created_at']) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.steamId64 == steamId64 &&
      other.personaName == personaName &&
      other.avatarUrl == avatarUrl &&
      other.alias == alias &&
      other.isOwnProfile == isOwnProfile &&
      other.isFamilyMember == isFamilyMember &&
      other.createdAtUnix == createdAtUnix;

  @override
  int get hashCode => Object.hash(
        steamId64,
        personaName,
        avatarUrl,
        alias,
        isOwnProfile,
        isFamilyMember,
        createdAtUnix,
      );

  @override
  String toString() => 'Profile($steamId64, $displayName)';
}

/// Juego con los tiempos que Steam haya comunicado.
///
/// Los tiempos se almacenan en **minutos**. Un dato desconocido se representa
/// como `null` en lugar de convertirse silenciosamente en cero.
class Game {
  const Game({
    required this.appId,
    this.name,
    this.playtime2Weeks = 0,
    this.playtimeForever,
    this.coverUrl,
    this.iconUrl,
  });

  final int appId;

  /// Nombre del juego. Puede faltar si Steam no lo proporciona.
  final String? name;

  /// Minutos de las últimas dos semanas. Steam siempre lo incluye en
  /// `GetRecentlyPlayedGames`; si faltase se conserva `0` y el total del
  /// perfil se sigue marcando como "comunicado".
  final int playtime2Weeks;

  /// Minutos acumulados. `null` significa "Steam no lo ha comunicado".
  final int? playtimeForever;

  final String? coverUrl;

  /// Icono pequeño del juego (`img_icon_url`), usado como recurso alternativo.
  final String? iconUrl;

  /// `true` cuando Steam ha comunicado el tiempo acumulado.
  bool get hasPlaytimeForever => playtimeForever != null;

  /// Etiqueta utilizable incluso si Steam no da el nombre.
  String get label {
    final String? n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'AppID $appId';
  }

  Game copyWith({
    int? appId,
    String? name,
    int? playtime2Weeks,
    int? playtimeForever,
    bool clearPlaytimeForever = false,
    String? coverUrl,
    String? iconUrl,
  }) {
    return Game(
      appId: appId ?? this.appId,
      name: name ?? this.name,
      playtime2Weeks: playtime2Weeks ?? this.playtime2Weeks,
      playtimeForever:
          clearPlaytimeForever ? null : (playtimeForever ?? this.playtimeForever),
      coverUrl: coverUrl ?? this.coverUrl,
      iconUrl: iconUrl ?? this.iconUrl,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'app_id': appId,
        'name': name,
        'playtime_2weeks': playtime2Weeks,
        'playtime_forever': playtimeForever,
        'has_playtime_forever': hasPlaytimeForever ? 1 : 0,
        'cover_url': coverUrl,
        'icon_url': iconUrl,
      };

  static Game fromMap(Map<String, Object?> map) => Game(
        appId: _asInt(map['app_id']) ?? 0,
        name: map['name'] as String?,
        playtime2Weeks: _nonNegative(_asInt(map['playtime_2weeks']) ?? 0),
        playtimeForever: map['playtime_forever'] == null
            ? null
            : _nonNegative(_asInt(map['playtime_forever']) ?? 0),
        coverUrl: map['cover_url'] as String?,
        iconUrl: map['icon_url'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is Game &&
      other.appId == appId &&
      other.name == name &&
      other.playtime2Weeks == playtime2Weeks &&
      other.playtimeForever == playtimeForever &&
      other.coverUrl == coverUrl &&
      other.iconUrl == iconUrl;

  @override
  int get hashCode => Object.hash(
        appId,
        name,
        playtime2Weeks,
        playtimeForever,
        coverUrl,
        iconUrl,
      );

  @override
  String toString() =>
      'Game($appId, $label, 2w: $playtime2Weeks min, forever: $playtimeForever)';
}

/// Actividad almacenada o recién consultada de un perfil.
class ProfileActivity {
  const ProfileActivity({
    required this.steamId64,
    this.personaName,
    this.avatarUrl,
    this.games = const <Game>[],
    this.status = FetchStatus.notFetched,
    this.statusMessage,
    this.fetchedAtUnix,
    this.lastSuccessAtUnix,
    this.fromCache = false,
    this.isStale = false,
  });

  final String steamId64;
  final String? personaName;
  final String? avatarUrl;

  /// Juegos ordenados por tiempo reciente descendente como orden por defecto.
  final List<Game> games;

  final FetchStatus status;
  final String? statusMessage;

  /// Momento del último intento de consulta.
  final int? fetchedAtUnix;

  /// Momento de la última consulta correcta (origen de los juegos guardados).
  final int? lastSuccessAtUnix;

  /// `true` cuando los juegos mostrados proceden de la caché local.
  final bool fromCache;

  /// `true` cuando los datos en caché superan la antigüedad considerada fresca
  /// o cuando el último intento de actualización falló.
  final bool isStale;

  /// Suma de minutos recientes comunicados por Steam.
  ///
  /// Devuelve `null` si Steam no entregó una respuesta válida, para no
  /// presentar un cero engañoso.
  int? get totalRecentMinutes {
    if (!status.isAnswered) return null;
    return _safeSum(games.map((Game g) => g.playtime2Weeks));
  }

  /// Suma de minutos acumulados.
  ///
  /// Devuelve `null` si Steam no comunicó el acumulado de *todos* los juegos:
  /// un total parcial se presentaría como si fuese completo.
  int? get totalForeverMinutes {
    if (!status.isAnswered) return null;
    if (games.isEmpty) return 0;
    if (games.any((Game g) => !g.hasPlaytimeForever)) return null;
    return _safeSum(games.map((Game g) => g.playtimeForever ?? 0));
  }

  /// `true` cuando el acumulado agregado está disponible.
  bool get hasCompleteForever => totalForeverMinutes != null;

  int get gamesCount => games.length;

  ProfileActivity copyWith({
    String? steamId64,
    String? personaName,
    String? avatarUrl,
    List<Game>? games,
    FetchStatus? status,
    String? statusMessage,
    bool clearStatusMessage = false,
    int? fetchedAtUnix,
    int? lastSuccessAtUnix,
    bool? fromCache,
    bool? isStale,
  }) {
    return ProfileActivity(
      steamId64: steamId64 ?? this.steamId64,
      personaName: personaName ?? this.personaName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      games: games ?? this.games,
      status: status ?? this.status,
      statusMessage:
          clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
      fetchedAtUnix: fetchedAtUnix ?? this.fetchedAtUnix,
      lastSuccessAtUnix: lastSuccessAtUnix ?? this.lastSuccessAtUnix,
      fromCache: fromCache ?? this.fromCache,
      isStale: isStale ?? this.isStale,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'steam_id64': steamId64,
        'status': status.name,
        'status_message': statusMessage,
        'fetched_at': fetchedAtUnix,
        'last_success_at': lastSuccessAtUnix,
        'from_cache': fromCache ? 1 : 0,
        'is_stale': isStale ? 1 : 0,
        'total_recent_minutes': totalRecentMinutes,
        'total_forever_minutes': totalForeverMinutes,
        'games_count': games.length,
      };

  static ProfileActivity fromMap(
    Map<String, Object?> map, {
    List<Game> games = const <Game>[],
    String? personaName,
    String? avatarUrl,
  }) {
    final String statusName = (map['status'] as String?) ?? FetchStatus.notFetched.name;
    return ProfileActivity(
      steamId64: (map['steam_id64'] as String?) ?? '',
      personaName: personaName,
      avatarUrl: avatarUrl,
      games: games,
      status: _statusFromName(statusName),
      statusMessage: map['status_message'] as String?,
      fetchedAtUnix: _asInt(map['fetched_at']),
      lastSuccessAtUnix: _asInt(map['last_success_at']),
      fromCache: _asBool(map['from_cache']),
      isStale: _asBool(map['is_stale']),
    );
  }

  @override
  String toString() =>
      'ProfileActivity($steamId64, ${status.name}, ${games.length} juegos)';
}

/// Preferencias persistidas entre sesiones.
class Preferences {
  const Preferences({
    this.hideLowActivity = false,
    this.lowActivityFilterMinutes = 30,
    this.moderateActivityMinutes = 120,
    this.highActivityMinutes = 480,
    this.showCovers = true,
    this.lastSelectedProfile,
    this.refreshOnOpen = true,
    this.openLastViewedSection = true,
    this.lastSection,
  });

  const Preferences.defaults()
      : hideLowActivity = false,
        lowActivityFilterMinutes = 30,
        moderateActivityMinutes = 120,
        highActivityMinutes = 480,
        showCovers = true,
        lastSelectedProfile = null,
        refreshOnOpen = true,
        openLastViewedSection = true,
        lastSection = null;

  /// Oculta los juegos por debajo de [lowActivityFilterMinutes] en pantalla.
  final bool hideLowActivity;

  /// Umbral por debajo del cual un juego se considera de actividad muy baja.
  final int lowActivityFilterMinutes;

  /// A partir de este valor la actividad del perfil es moderada.
  final int moderateActivityMinutes;

  /// A partir de este valor la actividad del perfil es alta.
  final int highActivityMinutes;

  final bool showCovers;

  /// Último integrante seleccionado en Recientes.
  final String? lastSelectedProfile;

  /// Intenta actualizar al abrir o volver al primer plano.
  final bool refreshOnOpen;

  /// Restaura la última sección al abrir.
  final bool openLastViewedSection;

  /// Nombre de la última sección visitada (`AppSection.name`).
  final String? lastSection;

  /// Devuelve unas preferencias coherentes:
  /// `1 <= low <= moderate < high <= máximo`.
  Preferences sanitized() {
    final int low = lowActivityFilterMinutes.clamp(0, AppConstants.maxActivityThresholdMinutes);
    int moderate = moderateActivityMinutes.clamp(1, AppConstants.maxActivityThresholdMinutes);
    int high = highActivityMinutes.clamp(1, AppConstants.maxActivityThresholdMinutes);
    if (moderate >= high) {
      // Si el usuario invierte los umbrales, se corrige de forma predecible.
      high = (moderate + 1).clamp(2, AppConstants.maxActivityThresholdMinutes);
      if (moderate >= high) moderate = high - 1;
    }
    final int lowClamped = low > moderate ? moderate : low;
    return Preferences(
      hideLowActivity: hideLowActivity,
      lowActivityFilterMinutes: lowClamped,
      moderateActivityMinutes: moderate,
      highActivityMinutes: high,
      showCovers: showCovers,
      lastSelectedProfile: lastSelectedProfile,
      refreshOnOpen: refreshOnOpen,
      openLastViewedSection: openLastViewedSection,
      lastSection: lastSection,
    );
  }

  Preferences copyWith({
    bool? hideLowActivity,
    int? lowActivityFilterMinutes,
    int? moderateActivityMinutes,
    int? highActivityMinutes,
    bool? showCovers,
    String? lastSelectedProfile,
    bool clearLastSelectedProfile = false,
    bool? refreshOnOpen,
    bool? openLastViewedSection,
    String? lastSection,
  }) {
    return Preferences(
      hideLowActivity: hideLowActivity ?? this.hideLowActivity,
      lowActivityFilterMinutes:
          lowActivityFilterMinutes ?? this.lowActivityFilterMinutes,
      moderateActivityMinutes:
          moderateActivityMinutes ?? this.moderateActivityMinutes,
      highActivityMinutes: highActivityMinutes ?? this.highActivityMinutes,
      showCovers: showCovers ?? this.showCovers,
      lastSelectedProfile: clearLastSelectedProfile
          ? null
          : (lastSelectedProfile ?? this.lastSelectedProfile),
      refreshOnOpen: refreshOnOpen ?? this.refreshOnOpen,
      openLastViewedSection: openLastViewedSection ?? this.openLastViewedSection,
      lastSection: lastSection ?? this.lastSection,
    );
  }

  /// Se serializa como `Map<String, String>` porque la tabla `preferences` es
  /// clave/valor y resulta legible y ampliable.
  Map<String, String> toKeyValueMap() => <String, String>{
        'hide_low_activity': hideLowActivity ? '1' : '0',
        'low_activity_filter_minutes': '$lowActivityFilterMinutes',
        'moderate_activity_minutes': '$moderateActivityMinutes',
        'high_activity_minutes': '$highActivityMinutes',
        'show_covers': showCovers ? '1' : '0',
        'last_selected_profile': lastSelectedProfile ?? '',
        'refresh_on_open': refreshOnOpen ? '1' : '0',
        'open_last_viewed_section': openLastViewedSection ? '1' : '0',
        'last_section': lastSection ?? '',
      };

  static Preferences fromKeyValueMap(Map<String, String> map) {
    const Preferences d = Preferences.defaults();
    return Preferences(
      hideLowActivity: map.containsKey('hide_low_activity')
          ? _asBool(map['hide_low_activity'])
          : d.hideLowActivity,
      lowActivityFilterMinutes: _asInt(map['low_activity_filter_minutes']) ??
          d.lowActivityFilterMinutes,
      moderateActivityMinutes:
          _asInt(map['moderate_activity_minutes']) ?? d.moderateActivityMinutes,
      highActivityMinutes:
          _asInt(map['high_activity_minutes']) ?? d.highActivityMinutes,
      showCovers: map.containsKey('show_covers')
          ? _asBool(map['show_covers'])
          : d.showCovers,
      lastSelectedProfile: _emptyToNull(map['last_selected_profile']),
      refreshOnOpen: map.containsKey('refresh_on_open')
          ? _asBool(map['refresh_on_open'])
          : d.refreshOnOpen,
      openLastViewedSection: map.containsKey('open_last_viewed_section')
          ? _asBool(map['open_last_viewed_section'])
          : d.openLastViewedSection,
      lastSection: _emptyToNull(map['last_section']),
    ).sanitized();
  }

  @override
  String toString() => 'Preferences(moderate: $moderateActivityMinutes, '
      'high: $highActivityMinutes, covers: $showCovers)';
}

// ---------------------------------------------------------------------------
// Utilidades internas de conversión defensiva.
// ---------------------------------------------------------------------------

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  if (value is bool) return value ? 1 : 0;
  return null;
}

bool _asBool(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String v = value.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'sí' || v == 'si';
  }
  return false;
}

String? _emptyToNull(String? value) {
  if (value == null) return null;
  final String t = value.trim();
  return t.isEmpty ? null : t;
}

int _nonNegative(int value) => value < 0 ? 0 : value;

/// Suma protegida frente a desbordamientos y valores negativos.
int _safeSum(Iterable<int> values) {
  int total = 0;
  for (final int v in values) {
    if (v <= 0) continue;
    final int next = total + v;
    if (next < total) return 0x7FFFFFFFFFFFFFFF; // Saturación en lugar de desbordar.
    total = next;
  }
  return total;
}

FetchStatus _statusFromName(String name) {
  for (final FetchStatus s in FetchStatus.values) {
    if (s.name == name) return s;
  }
  return FetchStatus.notFetched;
}
