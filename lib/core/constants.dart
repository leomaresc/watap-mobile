/// Constantes globales de WATAP Mobile.
///
/// Ningún valor de este archivo contiene secretos. La clave de la Steam Web API
/// se introduce en tiempo de ejecución y se guarda en el almacenamiento seguro
/// del dispositivo (ver `SecureApiKeyStore`).
class AppConstants {
  const AppConstants._();

  // --- Identidad de la aplicación -----------------------------------------

  static const String appName = 'WATAP';
  static const String appExpandedName = 'What Are They Actually Playing?';
  static const String appSubtitle = 'Actividad reciente de tus perfiles de Steam';
  static const String appVersion = '1.0.0';
  static const String appBuild = '1';

  // --- Steam ---------------------------------------------------------------

  static const String steamApiBaseUrl = 'https://api.steampowered.com';
  static const String steamCdnBaseUrl = 'https://cdn.cloudflare.steamstatic.com';
  static const String steamCommunityBaseUrl = 'https://steamcommunity.com';
  static const String steamStoreBaseUrl = 'https://store.steampowered.com';
  static const String steamMediaBaseUrl =
      'https://media.steampowered.com/steamcommunity/public/images/apps';

  /// Página oficial para solicitar una clave de Steam Web API.
  static const String steamApiKeyRegistrationUrl =
      'https://steamcommunity.com/dev/apikey';

  /// Documentación de los endpoints utilizados.
  static const String steamWebApiDocsUrl =
      'https://steamcommunity.com/dev';

  /// Encabezado admitido por la Steam Web API para enviar la clave.
  ///
  /// Se prefiere el encabezado frente al parámetro `key` de la URL para que la
  /// clave no aparezca en rutas ni en registros de intermediarios.
  static const String steamApiKeyHeader = 'x-webapi-key';

  /// Referencia con la que se guarda la clave en el almacén seguro del
  /// dispositivo. No es un secreto: es solo el nombre de la entrada.
  static const String apiKeyStorageKey = 'watap.steam.webapi.key';

  // --- Sesión de Steam y grupo familiar ------------------------------------

  /// Entradas del almacén seguro para la sesión de Steam.
  ///
  /// Son solo nombres de entrada; los valores (tokens) nunca se escriben en la
  /// base de datos ni en ningún archivo.
  static const String steamAccessTokenStorageKey = 'watap.steam.access.token';
  static const String steamRefreshTokenStorageKey = 'watap.steam.refresh.token';
  static const String steamIdStorageKey = 'watap.steam.id';
  static const String steamAccountNameStorageKey = 'watap.steam.account.name';

  /// Servicio de autenticación de Steam (flujo oficial del cliente).
  ///
  /// Endpoint **interno** (no listado en la documentación pública de Valve),
  /// pero es el mismo que usan el cliente y la aplicación móvil de Steam.
  static const String steamAuthBaseUrl = 'https://api.steampowered.com';

  /// `IPlayerService/GetRecentlyPlayedGames` y compañía aceptan tanto `key`
  /// como `access_token`; el grupo familiar **solo** acepta `access_token`.
  static const String steamFamilyGroupForUserPath =
      '/IFamilyGroupsService/GetFamilyGroupForUser/v1/';
  static const String steamFamilyGroupPath =
      '/IFamilyGroupsService/GetFamilyGroup/v1/';

  // --- Red -----------------------------------------------------------------

  /// Tiempo máximo por solicitud HTTPS.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Solicitudes simultáneas máximas contra la Steam Web API.
  static const int maxConcurrentRequests = 3;

  /// Límite documentado de la API para listas de SteamID64 en una sola llamada.
  static const int maxSteamIdsPerBatch = 100;

  /// Identificador de plataforma que se envía al iniciar sesión en Steam.
  ///
  /// 2 corresponde a "móvil" en el flujo de `IAuthenticationService`.
  static const String steamLoginPlatformType = '2';

  /// Nombre de dispositivo que Steam mostrará en la lista de sesiones.
  static const String steamLoginDeviceName = 'WATAP Mobile';

  /// Número máximo de consultas al estado del acceso antes de rendirse.
  ///
  /// Con el intervalo que indica Steam (unos 5 s), permite esperar algo más de
  /// dos minutos a que el usuario confirme desde su teléfono.
  static const int steamLoginMaxPollAttempts = 24;

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
