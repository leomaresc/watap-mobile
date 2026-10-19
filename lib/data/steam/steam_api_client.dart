/// Cliente HTTPS para los servicios de Steam usados por WATAP.
///
/// Responsabilidades:
/// - Exigir HTTPS en toda salida de red.
/// - Aplicar tiempos de espera finitos.
/// - Comprobar códigos HTTP e interpretarlos según el endpoint consultado.
/// - Distinguir errores de conexión, tiempo de espera y limitación de
///   solicitudes (HTTP 429, con `Retry-After` cuando Steam lo envía).
/// - Limitar las solicitudes simultáneas y evitar duplicados en vuelo.
///
/// **Autenticación**: la única credencial es el `webapi_token` de la sesión de
/// Steam (obtenido desde el WebView de inicio de sesión). Viaja como parámetro
/// `access_token` de la URL, sobre una conexión HTTPS directa a
/// `api.steampowered.com` (el mismo mecanismo que usa la propia web de Steam),
/// y **jamás se envía a `steamcommunity.com`** ni se escribe en registros.
///
/// El nombre, el avatar y la visibilidad de los perfiles se leen del XML
/// público de Steam Community (sin credencial), porque `ISteamUser` exige una
/// clave de Web API que WATAP no usa.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/models.dart';
import 'community_profile_parser.dart';
import 'steam_api_errors.dart';
import 'steam_api_urls.dart';
import 'steam_json_parsers.dart';

/// Política de interpretación de errores por endpoint.
///
/// Steam no documenta de forma exhaustiva los códigos de error de cada
/// endpoint, así que la interpretación se basa en la semántica documentada de
/// cada operación. Cada decisión está razonada en el código.
enum _EndpointPolicy {
  /// `GetRecentlyPlayedGames`: puede fallar por sesión rechazada o por
  /// privacidad del perfil. Un 401/403 se atribuye a privacidad o datos no
  /// disponibles; `RefreshCoordinator` distingue el caso de perfil público
  /// confirmado y lo informa con honestidad.
  recentlyPlayed,

  /// XML público de perfil en `steamcommunity.com`: **sin credenciales**. Un
  /// 401/403 ahí es un bloqueo del servidor, no un perfil inválido.
  communityProfile,
}

/// Respuesta HTTP mínima ya leída.
class _HttpResult {
  const _HttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// Cliente con control de concurrencia y deduplicación.
class SteamApiClient {
  SteamApiClient({
    http.Client? httpClient,
    Duration timeout = AppConstants.requestTimeout,
    int maxConcurrentRequests = AppConstants.maxConcurrentRequests,
    int maxTransientRetries = AppConstants.maxTransientRetries,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _timeout = timeout,
        _maxConcurrent = maxConcurrentRequests < 1 ? 1 : maxConcurrentRequests,
        _maxRetries = maxTransientRetries < 0 ? 0 : maxTransientRetries;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final int _maxConcurrent;
  final int _maxRetries;

  /// `webapi_token` de la sesión de Steam (obtenido desde el WebView).
  String? _accessToken;

  // --- Control de concurrencia ---------------------------------------------
  int _activeRequests = 0;
  final List<Completer<void>> _waitingSlots = <Completer<void>>[];

  // --- Deduplicación de solicitudes idénticas ------------------------------
  final Map<String, Future<_HttpResult>> _inFlight = <String, Future<_HttpResult>>{};

  // --- Ventana de espera tras un HTTP 429 ----------------------------------
  DateTime? _rateLimitedUntil;

  /// `true` cuando hay un token de sesión de Steam configurado.
  bool get hasAccessToken => (_accessToken ?? '').trim().isNotEmpty;

  /// Fecha hasta la que no se enviarán solicitudes por limitación del servidor.
  DateTime? get rateLimitedUntil => _rateLimitedUntil;

  /// Configura el `webapi_token` de la sesión de Steam.
  ///
  /// Este token autentica las consultas como parámetro `access_token` de la
  /// URL, sobre una conexión HTTPS directa a `api.steampowered.com`. Nunca se
  /// escribe en registros ni en mensajes de error.
  void setAccessToken(String? token) {
    final String? value = token?.trim();
    _accessToken = (value == null || value.isEmpty) ? null : value;
  }

  /// Cierra el cliente HTTP si fue creado internamente.
  void dispose() {
    for (final Completer<void> slot in _waitingSlots) {
      if (!slot.isCompleted) slot.complete();
    }
    _waitingSlots.clear();
    _inFlight.clear();
    if (_ownsClient) _client.close();
  }

  // -------------------------------------------------------------------------
  // Operaciones públicas
  // -------------------------------------------------------------------------

  /// Consulta los juegos jugados en las últimas dos semanas.
  ///
  /// Devuelve además la información necesaria para distinguir una respuesta
  /// válida sin juegos de un perfil privado.
  Future<RecentlyPlayedParseResult> fetchRecentlyPlayedGames(String steamId64) async {
    final Uri uri = SteamApiUrls.recentlyPlayed(steamId64);
    final _HttpResult result = await _get(
      uri,
      policy: _EndpointPolicy.recentlyPlayed,
      requiresAuth: true,
    );
    return parseRecentlyPlayedGames(result.body);
  }

  /// Lee el nombre, el avatar y la visibilidad de los perfiles indicados.
  ///
  /// Fuente: el **XML público de perfil de Steam Community** (sin
  /// credenciales). `ISteamUser/GetPlayerSummaries` exige una clave de Web API
  /// —responde HTTP 400 con un token— y WATAP no usa ese servicio.
  ///
  /// Un perfil inexistente se omite del resultado (el llamador lo interpreta
  /// como "perfil no encontrado"); un fallo de red o de parseo se propaga para
  /// que se informe con su estado real en lugar de fingir que no existe.
  Future<List<SteamPlayerSummary>> fetchPublicProfiles(
    List<String> steamId64s,
  ) async {
    final List<String> ids = steamId64s
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <SteamPlayerSummary>[];

    final List<SteamPlayerSummary> profiles = <SteamPlayerSummary>[];
    for (final String id in ids) {
      try {
        profiles.add(await _fetchCommunityProfile(id));
      } on SteamApiException catch (e) {
        if (e.kind == SteamApiErrorKind.invalidProfile) continue;
        rethrow;
      }
    }
    return profiles;
  }

  /// Lee un perfil público con el XML de Steam Community.
  ///
  /// La petición **no lleva ninguna credencial**: el token jamás se envía a
  /// `steamcommunity.com`.
  Future<SteamPlayerSummary> _fetchCommunityProfile(String steamId64) async {
    final Uri uri = SteamApiUrls.communityProfileXml(steamId64);
    final _HttpResult result = await _get(
      uri,
      policy: _EndpointPolicy.communityProfile,
      requiresAuth: false,
    );
    final CommunityProfileParseResult parsed =
        parseCommunityProfile(result.body);
    switch (parsed.status) {
      case CommunityProfileParseStatus.ok:
        return parsed.profile!.toSummary(steamId64);
      case CommunityProfileParseStatus.notFound:
        throw SteamApiException(
          kind: SteamApiErrorKind.invalidProfile,
          messageEs: defaultSteamErrorMessage(SteamApiErrorKind.invalidProfile),
          endpoint: uri.path,
        );
      case CommunityProfileParseStatus.malformed:
        throw SteamApiException(
          kind: SteamApiErrorKind.malformedResponse,
          messageEs:
              defaultSteamErrorMessage(SteamApiErrorKind.malformedResponse),
          endpoint: uri.path,
        );
    }
  }

  /// Resuelve un nombre personalizado de Steam a su SteamID64.
  ///
  /// Fuente: el XML público del perfil en `steamcommunity.com/id/{nombre}` —
  /// si existe, trae su `steamID64`; si no, Steam responde `<error>`.
  /// (`ResolveVanityURL` exige una clave de Web API, que WATAP no usa.)
  Future<VanityResolution> resolveVanityUrl(String vanity) async {
    final Uri uri = SteamApiUrls.communityVanityProfileXml(vanity);
    try {
      final _HttpResult result = await _get(
        uri,
        policy: _EndpointPolicy.communityProfile,
        requiresAuth: false,
      );
      final CommunityProfileParseResult parsed =
          parseCommunityProfile(result.body);
      switch (parsed.status) {
        case CommunityProfileParseStatus.ok:
          final String? id = parsed.profile?.steamId64;
          if (id == null || id.isEmpty) {
            return const VanityResolution(
              success: false,
              messageEs: 'Steam no informó el identificador de ese perfil.',
            );
          }
          return VanityResolution(success: true, steamId64: id);
        case CommunityProfileParseStatus.notFound:
          return const VanityResolution(
            success: false,
            messageEs:
                'No existe ningún perfil con ese nombre personalizado.',
          );
        case CommunityProfileParseStatus.malformed:
          return const VanityResolution(
            success: false,
            messageEs:
                'Steam devolvió una respuesta con un formato inesperado.',
          );
      }
    } on SteamApiException catch (e) {
      return VanityResolution(success: false, messageEs: e.messageEs);
    }
  }

  // -------------------------------------------------------------------------
  // Núcleo HTTP
  // -------------------------------------------------------------------------

  Future<_HttpResult> _get(
    Uri uri, {
    required _EndpointPolicy policy,
    required bool requiresAuth,
  }) {
    if (uri.scheme != 'https') {
      throw SteamApiException(
        kind: SteamApiErrorKind.unknown,
        messageEs: 'Por seguridad, WATAP solo realiza solicitudes HTTPS.',
        endpoint: uri.path,
      );
    }
    if (requiresAuth && !hasAccessToken) {
      throw const SteamApiException(
        kind: SteamApiErrorKind.incompleteConfiguration,
        messageEs: 'Conecta tu cuenta de Steam para consultar estos datos.',
      );
    }

    final Uri finalUri = _withAccessToken(uri);

    final DateTime? until = _rateLimitedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      throw SteamApiException(
        kind: SteamApiErrorKind.rateLimited,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.rateLimited),
        statusCode: 429,
        retryAfter: until.difference(DateTime.now()),
        endpoint: uri.path,
      );
    }

    // Deduplicación: dos peticiones idénticas comparten el mismo futuro.
    final String key = finalUri.toString();
    final Future<_HttpResult>? existing = _inFlight[key];
    if (existing != null) return existing;

    final Future<_HttpResult> request = _executeWithSlot(
      finalUri,
      policy: policy,
    );
    _inFlight[key] = request;
    return request.whenComplete(() {
      _inFlight.remove(key);
    });
  }

  /// Añade el `access_token` a la URL de la Steam Web API.
  ///
  /// El token **solo** viaja hacia `api.steampowered.com`: las consultas al
  /// XML público de `steamcommunity.com` se emiten sin credencial alguna.
  Uri _withAccessToken(Uri uri) {
    if (!hasAccessToken) return uri;
    if (uri.host != AppConstants.steamApiHost) return uri;
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'access_token': _accessToken!,
      },
    );
  }

  Future<_HttpResult> _executeWithSlot(
    Uri uri, {
    required _EndpointPolicy policy,
  }) async {
    await _acquireSlot();
    try {
      return await _executeWithRetries(uri, policy: policy);
    } finally {
      _releaseSlot();
    }
  }

  Future<_HttpResult> _executeWithRetries(
    Uri uri, {
    required _EndpointPolicy policy,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await _performRequest(uri, policy: policy);
      } on SteamApiException catch (e) {
        // Nunca se reintenta un 429: se respeta la ventana indicada por Steam.
        final bool retryable = e.kind == SteamApiErrorKind.network ||
            e.kind == SteamApiErrorKind.timeout ||
            (e.kind == SteamApiErrorKind.http && (e.statusCode ?? 0) >= 500);
        if (!retryable || attempt >= _maxRetries) rethrow;
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  Future<_HttpResult> _performRequest(
    Uri uri, {
    required _EndpointPolicy policy,
  }) async {
    // Ninguna cabecera de credencial: el token (si procede) va en la URL.
    final Map<String, String> headers = <String, String>{
      'Accept': '*/*',
    };

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw SteamApiException(
        kind: SteamApiErrorKind.timeout,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.timeout),
        endpoint: uri.path,
      );
    } on SocketException catch (e) {
      throw SteamApiException(
        kind: SteamApiErrorKind.network,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.network),
        endpoint: uri.path,
        technicalDetail: e.osError?.message,
      );
    } on http.ClientException catch (e) {
      throw SteamApiException(
        kind: SteamApiErrorKind.network,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.network),
        endpoint: uri.path,
        technicalDetail: e.message,
      );
    } on HandshakeException {
      throw SteamApiException(
        kind: SteamApiErrorKind.network,
        messageEs: 'No se pudo establecer una conexión segura con Steam.',
        endpoint: uri.path,
      );
    }

    final String body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _HttpResult(statusCode: response.statusCode, body: body);
    }
    throw _mapHttpError(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
      policy: policy,
      endpoint: uri.path,
    );
  }

  /// Steam devuelve UTF-8; se decodifica respetando el cuerpo si el paquete ya
  /// lo interpretó con otra codificación.
  String _decodeBody(http.Response response) {
    if (response.body.isNotEmpty) return response.body;
    if (response.bodyBytes.isEmpty) return '';
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  SteamApiException _mapHttpError({
    required int statusCode,
    required Map<String, String> headers,
    required String body,
    required _EndpointPolicy policy,
    required String endpoint,
  }) {
    switch (statusCode) {
      case 429:
        final Duration? retryAfter = _parseRetryAfter(headers['retry-after']);
        // Se respeta la ventana indicada por el servidor (con un tope) para no
        // seguir enviando solicitudes que serían rechazadas.
        final Duration effective = retryAfter ?? const Duration(minutes: 1);
        final Duration capped = effective > AppConstants.maxHonouredRetryAfter
            ? AppConstants.maxHonouredRetryAfter
            : effective;
        _rateLimitedUntil = DateTime.now().add(capped);
        return SteamApiException(
          kind: SteamApiErrorKind.rateLimited,
          messageEs: defaultSteamErrorMessage(SteamApiErrorKind.rateLimited),
          statusCode: statusCode,
          retryAfter: retryAfter,
          endpoint: endpoint,
        );

      case 401:
      case 403:
        // Interpretación según la semántica documentada del endpoint.
        switch (policy) {
          case _EndpointPolicy.recentlyPlayed:
            return SteamApiException(
              kind: SteamApiErrorKind.privateOrUnavailable,
              messageEs: defaultSteamErrorMessage(
                SteamApiErrorKind.privateOrUnavailable,
              ),
              statusCode: statusCode,
              endpoint: endpoint,
            );
          case _EndpointPolicy.communityProfile:
            // El XML público se pide sin credencial: un 401/403 ahí es un
            // bloqueo del servidor, no un perfil inválido.
            return SteamApiException(
              kind: SteamApiErrorKind.http,
              messageEs: defaultSteamErrorMessage(SteamApiErrorKind.http),
              statusCode: statusCode,
              endpoint: endpoint,
            );
        }

      case 400:
        // Steam responde 400 cuando la petición no tiene sentido (por ejemplo,
        // un parámetro ausente). Un perfil inexistente responde 200 con
        // <error>, nunca 400.
        return SteamApiException(
          kind: SteamApiErrorKind.http,
          messageEs: 'Steam rechazó la petición (error 400).',
          statusCode: statusCode,
          endpoint: endpoint,
        );

      default:
        if (statusCode >= 500) {
          return SteamApiException(
            kind: SteamApiErrorKind.http,
            messageEs: 'Steam no está disponible en este momento '
                '(error $statusCode). Inténtalo de nuevo más tarde.',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        return SteamApiException(
          kind: SteamApiErrorKind.http,
          messageEs: defaultSteamErrorMessage(SteamApiErrorKind.http),
          statusCode: statusCode,
          endpoint: endpoint,
          technicalDetail: body.isEmpty ? null : body.substring(0, body.length.clamp(0, 120)),
        );
    }
  }

  /// Interpreta el encabezado `Retry-After` (segundos o fecha HTTP).
  Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final String raw = value.trim();
    if (raw.isEmpty) return null;
    final int? seconds = int.tryParse(raw);
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }
    try {
      final DateTime date = HttpDate.parse(raw);
      final Duration diff = date.difference(DateTime.now().toUtc());
      return diff.isNegative ? null : diff;
    } catch (_) {
      return null;
    }
  }

  // --- Semáforo simple -----------------------------------------------------

  Future<void> _acquireSlot() async {
    if (_activeRequests < _maxConcurrent) {
      _activeRequests++;
      return;
    }
    final Completer<void> completer = Completer<void>();
    _waitingSlots.add(completer);
    await completer.future;
    _activeRequests++;
  }

  void _releaseSlot() {
    if (_activeRequests > 0) _activeRequests--;
    if (_waitingSlots.isNotEmpty && _activeRequests < _maxConcurrent) {
      final Completer<void> next = _waitingSlots.removeAt(0);
      if (!next.isCompleted) next.complete();
    }
  }
}
