/// Constantes globales de WATAP Mobile.
///
/// Ningún valor de este archivo contiene secretos. La única credencial es el
/// `webapi_token` de la sesión de Steam, que se obtiene del WebView de inicio
/// de sesión y se guarda en el almacenamiento seguro del dispositivo (ver
/// `SteamTokenStore`).
class AppConstants {
  const AppConstants._();

  // --- Identidad de la aplicación -----------------------------------------

  static const String appName = 'WATAP';
  static const String appExpandedName = 'What Are They Actually Playing?';
  static const String appSubtitle = 'Actividad reciente de tus perfiles de Steam';
  static const String appVersion = '1.5.0';
  static const String appBuild = '6';

  // --- Steam ---------------------------------------------------------------

  static const String steamApiBaseUrl = 'https://api.steampowered.com';

  /// Host de la Steam Web API. El token de sesión solo viaja hacia este host.
  static const String steamApiHost = 'api.steampowered.com';

  /// Host de Steam Community (XML público de perfil, sin credenciales).
  static const String steamCommunityHost = 'steamcommunity.com';
  static const String steamCdnBaseUrl = 'https://cdn.cloudflare.steamstatic.com';
  static const String steamCommunityBaseUrl = 'https://steamcommunity.com';
  static const String steamStoreBaseUrl = 'https://store.steampowered.com';
  static const String steamMediaBaseUrl =
      'https://media.steampowered.com/steamcommunity/public/images/apps';

  /// Documentación de los endpoints utilizados.
  static const String steamWebApiDocsUrl =
      'https://steamcommunity.com/dev';

  /// Nombre de la entrada del `webapi_token` de Steam en el almacén seguro.
  ///
  /// Es solo el nombre de la entrada; el valor (el token) nunca se escribe en
  /// la base de datos ni en ningún archivo.
  static const String steamTokenStorageKey = 'watap.steam.webapi.token';

  // --- Red
  //

  /// Tiempo máximo por solicitud HTTPS.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Límite de solicitudes simultáneas contra la Steam Web API.
  ///
  /// Steam admite como máximo 100 SteamID64 por llamada en los endpoints por
  /// lote; WATAP consulta los perfiles de forma individual (XML público).
  static const int maxConcurrentRequests = 3;

  /// Reintentos adicionales ante errores transitorios (5xx / red).
  static const int maxTransientRetries = 1;

  /// Espera máxima que se respetará automáticamente tras un HTTP 429.
  ///
  /// Si el servidor pide más tiempo, no se bloquea la interfaz: se informa al
  /// usuario y se deja de enviar solicitudes hasta que expire la ventana.
  static const Duration maxHonouredRetryAfter = Duration(seconds: 60);

  // --- Caché ---------------------------------------------------------------

  /// Antigüedad a partir de la cual la caché se marca como obsoleta (visual).
  static const Duration staleAfter = Duration(hours: 6);

  /// Tamaño máximo aproximado de la caché de imágenes.
  static const int maxImageCacheBytes = 120 * 1024 * 1024;

  // --- Base de datos -------------------------------------------------------

  static const String databaseFileName = 'watap.db';
  static const int databaseVersion = 4;

  /// Número de versión del esquema sobre el que se ejecutan las migraciones
  /// al abrir la base de datos.
  static const int databaseMigrationBaselineVersion = 1;

  // --- Preferencias --------------------------------------------------------

  static const int defaultLowActivityFilterMinutes = 30;
  static const int defaultModerateActivityMinutes = 120;
  static const int defaultHighActivityMinutes = 480;

  /// Máximo admitido para los umbrales de actividad (10 000 horas).
  static const int maxActivityThresholdMinutes = 600000;
}
