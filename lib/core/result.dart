/// Tipos de resultado usados por las capas de datos y servicios.
///
/// Se evita lanzar excepciones para los fallos esperados (red, privacidad,
/// clave inválida…). Así la interfaz siempre puede decidir qué mostrar sin
/// envolver todo en `try/catch`.
library;

/// Clasificación de un fallo, independiente del transporte utilizado.
enum FailureKind {
  /// No fue posible completar la operación por un problema de red.
  network,

  /// La operación excedió el tiempo máximo configurado.
  timeout,

  /// El servidor limitó las solicitudes (HTTP 429).
  rateLimited,

  /// El servidor confirmó que la credencial no es válida.
  invalidApiKey,

  /// El servidor denegó el acceso (privacidad o permisos insuficientes).
  forbidden,

  /// El recurso no existe o no pudo resolverse.
  notFound,

  /// La entrada del usuario es incorrecta.
  invalidInput,

  /// La respuesta no tiene el formato esperado o el JSON es inválido.
  invalidResponse,

  /// Error del servidor (5xx) o respuesta inesperada.
  server,

  /// La operación se descartó porque ya no es relevante (cancelación).
  cancelled,

  /// Falta configuración necesaria (por ejemplo, la clave de API).
  incompleteConfiguration,

  /// Causa no determinada.
  unknown,
}

/// Fallo con información suficiente para mostrarse al usuario en español.
class AppFailure implements Exception {
  const AppFailure({
    required this.kind,
    required this.messageEs,
    this.httpStatus,
    this.retryAfter,
    this.technicalDetail,
  });

  final FailureKind kind;

  /// Mensaje apto para mostrarse en la interfaz. Nunca contiene la clave.
  final String messageEs;

  /// Código HTTP, cuando exista.
  final int? httpStatus;

  /// Espera indicada por el servidor tras un HTTP 429.
  final Duration? retryAfter;

  /// Detalle técnico opcional (sin secretos) útil en diagnóstico.
  final String? technicalDetail;

  /// `true` cuando tiene sentido ofrecer un botón de "reintentar".
  bool get isRecoverable => switch (kind) {
        FailureKind.network => true,
        FailureKind.timeout => true,
        FailureKind.rateLimited => true,
        FailureKind.server => true,
        FailureKind.unknown => true,
        _ => false,
      };

  @override
  String toString() =>
      'AppFailure(kind: $kind, httpStatus: $httpStatus, message: $messageEs)';
}

/// Envoltorio mínimo de éxito o fallo.
class Result<T> {
  const Result._(this.value, this.failure);

  factory Result.ok(T value) => Result<T>._(value, null);

  factory Result.fail(AppFailure failure) => Result<T>._(null, failure);

  final T? value;
  final AppFailure? failure;

  bool get isSuccess => failure == null;

  bool get isFailure => failure != null;

  /// Devuelve el valor o lanza una [StateError] si hubo fallo.
  T get requireValue {
    final T? v = value;
    if (v == null || failure != null) {
      throw StateError('Result sin valor: ${failure?.messageEs}');
    }
    return v;
  }

  R when<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) fail,
  }) {
    final T? v = value;
    if (failure != null || v == null) {
      return fail(failure ?? const AppFailure(
        kind: FailureKind.unknown,
        messageEs: 'No se pudo completar la operación.',
      ));
    }
    return ok(v);
  }
}
