/// Cliente HTTPS para la Steam Web API pública.
///
/// Responsabilidades:
/// - Exigir HTTPS en toda salida de red.
/// - Aplicar tiempos de espera finitos.
/// - Comprobar códigos HTTP e interpretarlos según el endpoint consultado.
/// - Distinguir errores de conexión, tiempo de espera y limitación de
///   solicitudes (HTTP 429, con `Retry-After` cuando Steam lo envía).
/// - Limitar las solicitudes simultáneas y evitar duplicados en vuelo.
/// - Enviar la clave en el encabezado `x-webapi-key`, nunca en la URL ni en
///   ningún registro.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/models.dart';
import 'steam_api_errors.dart';
import 'steam_api_urls.dart';
import 'steam_json_parsers.dart';

/// Resultado de comprobar la clave configurada.
class ApiKeyCheckResult {
  const ApiKeyCheckResult({
    required this.keyAccepted,
    required this.profileFound,
    required this.messageEs,
    this.technicalDetail,
  });

  /// `true` si Steam aceptó la clave, `false` si la rechazó, `null` si la
  /// respuesta no permite determinarlo.
  final bool? keyAccepted;

  /// `true`/`false` si además se pudo comprobar el perfil indicado,
  /// `null` si no se proporcionó ninguno o no se pudo determinar.
  final bool? profileFound;

  final String messageEs;

  /// Detalle técnico sin secretos (código HTTP, endpoint…).
  final String? technicalDetail;

  bool get isConclusive => keyAccepted != null;
}

/// Política de interpretación de errores por endpoint.
///
/// Steam no documenta de forma exhaustiva los códigos de error de cada
/// endpoint, así que la interpretación se basa en la semántica documentada de
/// cada operación. Cada decisión está razonada en el código.
enum _EndpointPolicy {
  /// `GetPlayerSummaries`: devuelve datos públicos y exige una clave válida.
  /// Por eso un 401/403 solo puede significar credencial rechazada.
  summaries,

  /// `GetRecentlyPlayedGames`: puede fallar por clave o por privacidad.
  /// Como el flujo comprueba antes la clave con `GetPlayerSummaries`, un
  /// 401/403 aquí se atribuye a privacidad o datos no disponibles.
  recentlyPlayed,

  /// `ResolveVanityURL`: la respuesta documenta `success`/`message`; un
  /// 401/403 indica credencial rechazada.
  vanity,
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

  String? _apiKey;

  // --- Control de concurrencia ---------------------------------------------
  int _activeRequests = 0;
  final List<Completer<void>> _waitingSlots = <Completer<void>>[];

  // --- Deduplicación de solicitudes idénticas ------------------------------
  final Map<String, Future<_HttpResult>> _inFlight = <String, Future<_HttpResult>>{};

  // --- Ventana de espera tras un HTTP 429 ----------------------------------
  DateTime? _rateLimitedUntil;

  /// `true` cuando hay una clave configurada para esta sesión.
  bool get hasApiKey => (_apiKey ?? '').trim().isNotEmpty;

  /// Fecha hasta la que no se enviarán solicitudes por limitación del servidor.
  DateTime? get rateLimitedUntil => _rateLimitedUntil;

  /// Configura la clave que se enviará en el encabezado `x-webapi-key`.
  ///
  /// Pasar `null` la elimina de memoria. La clave nunca se escribe en registros.
  void setApiKey(String? apiKey) {
    final String? value = apiKey?.trim();
    _apiKey = (value == null || value.isEmpty) ? null : value;
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
      requiresKey: true,
    );
    return parseRecentlyPlayedGames(result.body);
  }

  /// Consulta los resúmenes (nombre y avatar) de hasta 100 perfiles por lote.
  Future<List<SteamPlayerSummary>> fetchPlayerSummaries(
    List<String> steamId64s,
  ) async {
    final List<String> ids = steamId64s
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <SteamPlayerSummary>[];

    final List<SteamPlayerSummary> summaries = <SteamPlayerSummary>[];
    for (int i = 0; i < ids.length; i += AppConstants.maxSteamIdsPerBatch) {
      final int end = (i + AppConstants.maxSteamIdsPerBatch) > ids.length
          ? ids.length
          : i + AppConstants.maxSteamIdsPerBatch;
      final List<String> batch = ids.sublist(i, end);
      final Uri uri = SteamApiUrls.playerSummaries(batch);
      final _HttpResult result = await _get(
        uri,
        policy: _EndpointPolicy.summaries,
        requiresKey: true,
      );
      summaries.addAll(parsePlayerSummaries(result.body));
    }
    return summaries;
  }

  /// Resuelve un nombre personalizado de Steam a su SteamID64.
  Future<VanityResolution> resolveVanityUrl(String vanity) async {
    final Uri uri = SteamApiUrls.resolveVanityUrl(vanity);
    final _HttpResult result = await _get(
      uri,
      policy: _EndpointPolicy.vanity,
      requiresKey: false,
    );
    return parseVanityResolution(result.body);
  }

  /// Comprueba la clave configurada usando un perfil conocido por el usuario.
  ///
  /// No existe un endpoint de "prueba de clave" en Steam: la comprobación se
  /// realiza sobre `GetPlayerSummaries`, que exige una clave válida y devuelve
  /// datos públicos. Es una comprobación real, no simulada.
  Future<ApiKeyCheckResult> verifyApiKey({String? steamId64}) async {
    if (!hasApiKey) {
      return const ApiKeyCheckResult(
        keyAccepted: false,
        profileFound: null,
        messageEs: 'No hay ninguna clave de Steam Web API configurada.',
      );
    }
    try {
      if (steamId64 == null || steamId64.trim().isEmpty) {
        // Sin perfil propio: se consulta siempre la misma cuenta conocida de
        // Valve ("Valve" 76561197960435530). Es un dato público y estático que
        // permite comprobar la credencial sin depender de perfiles del usuario.
        final List<SteamPlayerSummary> probe =
            await fetchPlayerSummaries(const <String>['76561197960435530']);
        if (probe.isEmpty) {
          return const ApiKeyCheckResult(
            keyAccepted: null,
            profileFound: null,
            messageEs: 'Steam respondió sin datos para la consulta de '
                'comprobación. No es posible determinar si la clave es válida.',
          );
        }
        return const ApiKeyCheckResult(
          keyAccepted: true,
          profileFound: null,
          messageEs: 'La clave funciona: Steam ha aceptado la consulta.',
        );
      }

      final String id = steamId64.trim();
      final List<SteamPlayerSummary> summaries =
          await fetchPlayerSummaries(<String>[id]);
      final bool found = summaries.any((SteamPlayerSummary s) => s.steamId64 == id);
      return ApiKeyCheckResult(
        keyAccepted: true,
        profileFound: found,
        messageEs: found
            ? 'La clave es válida y el perfil responde correctamente.'
            : 'La clave es válida, pero Steam no reconoce el perfil $id. '
                'Comprueba el SteamID64.',
      );
    } on SteamApiException catch (e) {
      if (e.kind == SteamApiErrorKind.invalidApiKey) {
        return ApiKeyCheckResult(
          keyAccepted: false,
          profileFound: null,
          messageEs: 'Steam ha rechazado la clave: no es válida o está revocada.',
          technicalDetail: 'HTTP ${e.statusCode}',
        );
      }
      return ApiKeyCheckResult(
        keyAccepted: null,
        profileFound: null,
        messageEs: '${e.messageEs} No se puede confirmar el estado de la clave.',
        technicalDetail: 'HTTP ${e.statusCode} · ${e.kind.name}',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Núcleo HTTP
  // -------------------------------------------------------------------------

  Future<_HttpResult> _get(
    Uri uri, {
    required _EndpointPolicy policy,
    required bool requiresKey,
  }) {
    if (uri.scheme != 'https') {
      throw SteamApiException(
        kind: SteamApiErrorKind.unknown,
        messageEs: 'Por seguridad, WATAP solo realiza solicitudes HTTPS.',
        endpoint: uri.path,
      );
    }
    if (requiresKey && !hasApiKey) {
      throw const SteamApiException(
        kind: SteamApiErrorKind.incompleteConfiguration,
        messageEs: 'Falta la clave de Steam Web API.',
      );
    }

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
    final String key = '${uri.toString()}|key:$requiresKey';
    final Future<_HttpResult>? existing = _inFlight[key];
    if (existing != null) return existing;

    final Future<_HttpResult> request = _executeWithSlot(
      uri,
      policy: policy,
      requiresKey: requiresKey,
    );
    _inFlight[key] = request;
    return request.whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<_HttpResult> _executeWithSlot(
    Uri uri, {
    required _EndpointPolicy policy,
    required bool requiresKey,
  }) async {
    await _acquireSlot();
    try {
      return await _executeWithRetries(
        uri,
        policy: policy,
        requiresKey: requiresKey,
      );
    } finally {
      _releaseSlot();
    }
  }

  Future<_HttpResult> _executeWithRetries(
    Uri uri, {
    required _EndpointPolicy policy,
    required bool requiresKey,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await _performRequest(
          uri,
          policy: policy,
          requiresKey: requiresKey,
        );
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
    required bool requiresKey,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };
    if (requiresKey || hasApiKey) {
      // La clave viaja únicamente en el encabezado. Nunca se registra.
      final String? key = _apiKey;
      if (key != null) headers[AppConstants.steamApiKeyHeader] = key;
    }

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
          case _EndpointPolicy.summaries:
          case _EndpointPolicy.vanity:
            return SteamApiException(
              kind: SteamApiErrorKind.invalidApiKey,
              messageEs: defaultSteamErrorMessage(SteamApiErrorKind.invalidApiKey),
              statusCode: statusCode,
              endpoint: endpoint,
            );
          case _EndpointPolicy.recentlyPlayed:
            return SteamApiException(
              kind: SteamApiErrorKind.privateOrUnavailable,
              messageEs: defaultSteamErrorMessage(
                SteamApiErrorKind.privateOrUnavailable,
              ),
              statusCode: statusCode,
              endpoint: endpoint,
            );
        }

      case 400:
        return SteamApiException(
          kind: SteamApiErrorKind.invalidProfile,
          messageEs: defaultSteamErrorMessage(SteamApiErrorKind.invalidProfile),
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
