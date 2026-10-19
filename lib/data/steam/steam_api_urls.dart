/// Construcción de las URLs utilizadas por WATAP Mobile.
///
/// Solo se emplean endpoints públicos de Valve: la Steam Web API, el XML
/// público de perfil de Steam Community y el CDN público de imágenes. **Ninguna
/// URL contiene credenciales por sí misma.**
///
/// El `access_token` de sesión sí viaja como parámetro de la URL — Steam exige
/// `GET` y esa es la forma en que la propia web de Steam lo envía. Va siempre
/// sobre una conexión HTTPS directa a `api.steampowered.com`, **nunca** a
/// `steamcommunity.com` (el XML público se consulta sin credencial) y jamás se
/// registra en la aplicación.
///
/// Funciones puras y probadas en `test/data/steam_api_urls_test.dart`.
library;

import '../../core/constants.dart';

/// Rutas de los endpoints utilizados.
class SteamApiEndpoints {
  const SteamApiEndpoints._();

  /// Juegos jugados en las últimas dos semanas.
  static const String recentlyPlayed =
      '/IPlayerService/GetRecentlyPlayedGames/v1/';

  /// Grupo familiar de la cuenta autenticada.
  ///
  /// Endpoint **interno** (sin documentación pública de Valve): solo acepta un
  /// `access_token` de sesión de Steam.
  static const String familyGroupForUser =
      '/IFamilyGroupsService/GetFamilyGroupForUser/v1/';

  /// Detalle de un grupo familiar (nombre e integrantes).
  static const String familyGroup =
      '/IFamilyGroupsService/GetFamilyGroup/v1/';
}

/// Constructores de URL de la aplicación.
class SteamApiUrls {
  const SteamApiUrls._();

  static const String _apiBase = AppConstants.steamApiBaseUrl;

  /// `IPlayerService/GetRecentlyPlayedGames/v1`
  ///
  /// Devuelve el nombre del juego, el AppID, los minutos de las últimas dos
  /// semanas y el tiempo acumulado cuando Steam lo proporciona.
  static Uri recentlyPlayed(String steamId64, {bool includeAppInfo = true}) {
    return Uri.parse('$_apiBase${SteamApiEndpoints.recentlyPlayed}').replace(
      queryParameters: <String, String>{
        'steamid': steamId64,
        'include_appinfo': includeAppInfo ? '1' : '0',
        'format': 'json',
      },
    );
  }

  /// XML público del perfil de Steam Community (fuente de nombre, avatar y
  /// visibilidad, **sin credenciales**).
  ///
  /// Steam Community publica el XML oficial de un perfil bajo
  /// `https://steamcommunity.com/profiles/{id}?xml=1`: datos estructurados,
  /// nunca HTML. (`ISteamUser/GetPlayerSummaries` exige una clave de Web API
  /// que WATAP no usa.)
  static Uri communityProfileXml(String steamId64) {
    return Uri.https(
      AppConstants.steamCommunityHost,
      '/profiles/$steamId64',
      <String, String>{'xml': '1'},
    );
  }

  /// XML público del perfil asociado a un nombre personalizado (vanity).
  ///
  /// Permite resolver `steamcommunity.com/id/ejemplo` a SteamID64 sin
  /// credencial: si no existe, Steam responde
  /// `<response><error>…</error></response>`.
  static Uri communityVanityProfileXml(String vanity) {
    return Uri.https(
      AppConstants.steamCommunityHost,
      '/id/${vanity.trim()}',
      <String, String>{'xml': '1'},
    );
  }

  /// `IFamilyGroupsService/GetFamilyGroupForUser/v1`
  ///
  /// Steam exige **GET** para este servicio (el `POST` devuelve HTTP 405), así
  /// que el `access_token` viaja como parámetro de la URL sobre una conexión
  /// HTTPS directa a `api.steampowered.com`.
  static Uri familyGroupForUser(String accessToken) {
    return Uri.parse('$_apiBase${SteamApiEndpoints.familyGroupForUser}').replace(
      queryParameters: <String, String>{
        'access_token': accessToken.trim(),
        'format': 'json',
      },
    );
  }

  /// `IFamilyGroupsService/GetFamilyGroup/v1`
  static Uri familyGroup(String accessToken, String familyGroupId) {
    return Uri.parse('$_apiBase${SteamApiEndpoints.familyGroup}').replace(
      queryParameters: <String, String>{
        'access_token': accessToken.trim(),
        'family_groupid': familyGroupId,
        'format': 'json',
      },
    );
  }

  /// Portada oficial del juego en el CDN público de Steam.
  ///
  /// Es el recurso que usa Steam para la cabecera de la ficha del juego.
  static Uri gameCover(int appId) => Uri.parse(
        '${AppConstants.steamCdnBaseUrl}/steam/apps/$appId/header.jpg',
      );

  /// Recurso de imagen de reserva (más pequeño) del CDN público de Steam.
  static Uri gameCapsule(int appId) => Uri.parse(
        '${AppConstants.steamCdnBaseUrl}/steam/apps/$appId/capsule_231x87.jpg',
      );

  /// Icono del juego publicado en el CDN de la comunidad de Steam.
  ///
  /// [iconHash] es el campo `img_icon_url` de la respuesta de Steam.
  static Uri gameIcon(int appId, String iconHash) => Uri.parse(
        '${AppConstants.steamMediaBaseUrl}/$appId/$iconHash.jpg',
      );

  /// Página del juego en la tienda de Steam.
  static Uri storePage(int appId) =>
      Uri.parse('${AppConstants.steamStoreBaseUrl}/app/$appId');

  /// Perfil público de Steam a partir del SteamID64.
  static Uri communityProfile(String steamId64) =>
      Uri.parse('${AppConstants.steamCommunityBaseUrl}/profiles/$steamId64');

  /// Perfil público de Steam a partir del nombre personalizado.
  static Uri communityVanity(String vanity) =>
      Uri.parse('${AppConstants.steamCommunityBaseUrl}/id/$vanity');
}
