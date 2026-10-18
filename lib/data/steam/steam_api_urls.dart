/// Construcción de las URLs utilizadas por WATAP Mobile.
///
/// Solo se emplean endpoints públicos y documentados de la Steam Web API y el
/// CDN público de imágenes. **Ninguna URL contiene la clave de API**: la clave
/// viaja en el encabezado `x-webapi-key` (ver `SteamApiClient`), de modo que no
/// aparece en rutas, cachés intermedias ni registros.
///
/// Funciones puras y probadas en `test/data/steam_api_urls_test.dart`.
library;

import '../../core/constants.dart';

/// Rutas de los endpoints documentados utilizados.
class SteamApiEndpoints {
  const SteamApiEndpoints._();

  /// Juegos jugados en las últimas dos semanas.
  static const String recentlyPlayed =
      '/IPlayerService/GetRecentlyPlayedGames/v1/';

  /// Resúmenes públicos de perfiles (nombre y avatar).
  static const String playerSummaries = '/ISteamUser/GetPlayerSummaries/v2/';

  /// Resolución de un nombre personalizado a SteamID64.
  static const String resolveVanityUrl = '/ISteamUser/ResolveVanityURL/v1/';

  // --- Servicios internos del cliente de Steam -----------------------------
  //
  // No aparecen en la documentación pública de Valve, pero son los mismos que
  // usa el cliente oficial. Todos exigen un `access_token` de una sesión de
  // Steam iniciada; la clave de Web API no sirve para ellos.

  /// Grupo familiar de la cuenta autenticada.
  static const String familyGroupForUser =
      '/IFamilyGroupsService/GetFamilyGroupForUser/v1/';

  /// Detalle de un grupo familiar (nombre e integrantes).
  static const String familyGroup = '/IFamilyGroupsService/GetFamilyGroup/v1/';

  /// `IAuthenticationService`: clave pública para cifrar la contraseña.
  static const String passwordRsaPublicKey =
      '/IAuthenticationService/GetPasswordRSAPublicKey/v1/';

  /// `IAuthenticationService`: inicio de sesión con credenciales.
  static const String beginAuthSession =
      '/IAuthenticationService/BeginAuthSessionViaCredentials/v1/';

  /// `IAuthenticationService`: entrega del código de Steam Guard.
  static const String updateAuthSessionWithGuardCode =
      '/IAuthenticationService/UpdateAuthSessionWithSteamGuardCode/v1/';

  /// `IAuthenticationService`: consulta del estado del inicio de sesión.
  static const String pollAuthSessionStatus =
      '/IAuthenticationService/PollAuthSessionStatus/v1/';

  /// `IAuthenticationService`: renovación del token de acceso.
  static const String generateAccessTokenForApp =
      '/IAuthenticationService/GenerateAccessTokenForApp/v1/';
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

  /// `ISteamUser/GetPlayerSummaries/v2`
  ///
  /// Steam admite como máximo 100 SteamID64 por llamada; el llamador debe
  /// trocear la lista (ver `SteamApiClient.fetchPlayerSummaries`).
  static Uri playerSummaries(List<String> steamId64s) {
    final List<String> ids = steamId64s
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .take(AppConstants.maxSteamIdsPerBatch)
        .toList(growable: false);
    return Uri.parse('$_apiBase${SteamApiEndpoints.playerSummaries}').replace(
      queryParameters: <String, String>{
        'steamids': ids.join(','),
        'format': 'json',
      },
    );
  }

  /// `ISteamUser/ResolveVanityURL/v1`
  static Uri resolveVanityUrl(String vanityUrl) {
    return Uri.parse('$_apiBase${SteamApiEndpoints.resolveVanityUrl}').replace(
      queryParameters: <String, String>{
        'vanityurl': vanityUrl.trim(),
        'format': 'json',
      },
    );
  }

  /// Servicio interno de Steam (`api.steampowered.com`).
  ///
  /// Ni la clave de Web API ni el `access_token` viajan aquí: se envían en el
  /// cuerpo de la solicitud `POST`, de modo que nunca aparecen en una URL.
  static Uri authService(String path) =>
      Uri.parse('${AppConstants.steamAuthBaseUrl}$path');

  /// `IFamilyGroupsService/GetFamilyGroupForUser/v1`
  static Uri familyGroupForUser() =>
      Uri.parse('$_apiBase${SteamApiEndpoints.familyGroupForUser}');

  /// `IFamilyGroupsService/GetFamilyGroup/v1`
  static Uri familyGroup() =>
      Uri.parse('$_apiBase${SteamApiEndpoints.familyGroup}');

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

  /// Página oficial para solicitar una clave de Steam Web API.
  static Uri apiKeyRegistration() =>
      Uri.parse(AppConstants.steamApiKeyRegistrationUrl);
}
