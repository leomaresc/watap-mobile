/// Errores de la capa de red de Steam.
///
/// Se separan de `AppFailure` para mantener la lógica HTTP aislada de la
/// interfaz. `SteamApiErrorKind` se traduce a `FetchStatus` en un único punto.
library;

import '../../core/models.dart';

/// Causa técnica de un fallo al hablar con la Steam Web API.
enum SteamApiErrorKind {
  /// Fallo de conexión (DNS, socket, TLS…).
  network,

  /// Tiempo de espera agotado.
  timeout,

  /// HTTP 429: se alcanzó el límite de solicitudes.
  rateLimited,

  /// Acceso denegado o datos no disponibles por privacidad.
  privateOrUnavailable,

  /// El perfil indicado no existe o no puede resolverse.
  invalidProfile,

  /// JSON inválido o estructura inesperada.
  malformedResponse,

  /// Otro código HTTP no contemplado.
  http,

  /// Falta la sesión de Steam (conexión con la cuenta).
  incompleteConfiguration,

  /// Credenciales de sesión rechazadas (token de Steam caducado o inválido).
  invalidCredentials,

  /// Operación descartada por cancelación o cambio de ciclo de vida.
  cancelled,

  /// Causa desconocida.
  unknown,
}

/// Excepción interna de la capa de datos de Steam.
///
/// Nunca contiene el token de sesión ni el cuerpo completo de una respuesta
/// potencialmente sensible: solo el mensaje y el código de estado.
class SteamApiException implements Exception {
  const SteamApiException({
    required this.kind,
    required this.messageEs,
    this.statusCode,
    this.retryAfter,
    this.endpoint,
    this.technicalDetail,
  });

  final SteamApiErrorKind kind;
  final String messageEs;
  final int? statusCode;
  final Duration? retryAfter;

  /// Ruta del endpoint invocado (sin credenciales).
  final String? endpoint;

  final String? technicalDetail;

  /// `true` cuando el error puede resolverse con un nuevo intento.
  bool get isTransient => switch (kind) {
        SteamApiErrorKind.network => true,
        SteamApiErrorKind.timeout => true,
        SteamApiErrorKind.rateLimited => true,
        SteamApiErrorKind.http => true,
        SteamApiErrorKind.unknown => true,
        _ => false,
      };

  @override
  String toString() =>
      'SteamApiException(kind: $kind, status: $statusCode, endpoint: $endpoint)';
}

/// Traduce un fallo técnico al estado que se muestra en la interfaz.
FetchStatus fetchStatusForSteamError(SteamApiErrorKind kind) => switch (kind) {
      SteamApiErrorKind.network => FetchStatus.networkError,
      SteamApiErrorKind.timeout => FetchStatus.networkError,
      SteamApiErrorKind.rateLimited => FetchStatus.rateLimited,
      SteamApiErrorKind.privateOrUnavailable => FetchStatus.privateOrUnavailable,
      SteamApiErrorKind.invalidProfile => FetchStatus.invalidProfile,
      SteamApiErrorKind.malformedResponse => FetchStatus.malformedResponse,
      SteamApiErrorKind.incompleteConfiguration =>
        FetchStatus.incompleteConfiguration,
      SteamApiErrorKind.invalidCredentials => FetchStatus.incompleteConfiguration,
      SteamApiErrorKind.cancelled => FetchStatus.notFetched,
      SteamApiErrorKind.http => FetchStatus.networkError,
      SteamApiErrorKind.unknown => FetchStatus.networkError,
    };

/// Mensaje por defecto en español para cada causa técnica.
String defaultSteamErrorMessage(SteamApiErrorKind kind) => switch (kind) {
      SteamApiErrorKind.network =>
        'No se pudo conectar con Steam. Comprueba tu conexión a Internet.',
      SteamApiErrorKind.timeout =>
        'Steam tardó demasiado en responder. Vuelve a intentarlo.',
      SteamApiErrorKind.rateLimited =>
        'Steam ha limitado las solicitudes (error 429). Espera unos minutos antes de volver a actualizar.',
      SteamApiErrorKind.privateOrUnavailable =>
        'Steam no ha entregado los datos: el perfil es privado o sus detalles de juego están restringidos.',
      SteamApiErrorKind.invalidProfile =>
        'Steam no reconoce ese perfil. Comprueba el SteamID64 o el nombre personalizado.',
      SteamApiErrorKind.malformedResponse =>
        'Steam devolvió una respuesta con un formato inesperado.',
      SteamApiErrorKind.http =>
        'Steam devolvió una respuesta inesperada.',
      SteamApiErrorKind.incompleteConfiguration =>
        'Conecta tu cuenta de Steam para consultar estos datos.',
      SteamApiErrorKind.invalidCredentials =>
        'La sesión de Steam no es válida o ha caducado. Conecta tu cuenta de '
        'nuevo para obtener un token actualizado.',
      SteamApiErrorKind.cancelled => 'Consulta descartada.',
      SteamApiErrorKind.unknown => 'No se pudo completar la consulta a Steam.',
    };
