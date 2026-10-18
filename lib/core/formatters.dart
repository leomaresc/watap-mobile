/// Funciones puras de formateo y clasificación.
///
/// Todas son deterministas y no dependen de la interfaz ni de la red, por lo
/// que se prueban directamente en `test/core/formatters_test.dart`.
library;

import 'constants.dart';
import 'models.dart';

/// Guion que representa un dato desconocido.
const String kUnknownValue = '—';

/// Formatea minutos como `8 h 35 min`, `45 min` o `2 h`.
///
/// Devuelve un guion si el valor es `null` (dato no comunicado por Steam).
String formatMinutes(int? minutes) {
  if (minutes == null) return kUnknownValue;
  if (minutes <= 0) return '0 min';
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

/// Igual que [formatMinutes] pero con el sufijo indicado (por ejemplo `min`).
String formatMinutesWithSuffix(int? minutes, {String suffix = ''}) {
  final String base = formatMinutes(minutes);
  if (base == kUnknownValue || suffix.isEmpty) return base;
  return '$base$suffix';
}

/// Formatea un entero con separador de miles simple y predecible.
String formatNumber(int? value) {
  if (value == null) return kUnknownValue;
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$out';
}

/// Formatea una marca de tiempo Unix (segundos) con el formato local
/// `dd/MM/aaaa HH:mm`.
String formatLocalDateTime(int? unixSeconds) {
  if (unixSeconds == null || unixSeconds <= 0) return kUnknownValue;
  final DateTime dt =
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true).toLocal();
  final String d = dt.day.toString().padLeft(2, '0');
  final String m = dt.month.toString().padLeft(2, '0');
  final String y = dt.year.toString().padLeft(4, '0');
  final String hh = dt.hour.toString().padLeft(2, '0');
  final String mm = dt.minute.toString().padLeft(2, '0');
  return '$d/$m/$y $hh:$mm';
}

/// Formatea un tiempo relativo en español: `hace 5 min`, `hace 3 h`,
/// `hace 2 d`. Devuelve `nunca` si no hay marca de tiempo.
String formatRelativeTime(int? unixSeconds, {DateTime? now}) {
  if (unixSeconds == null || unixSeconds <= 0) return 'nunca';
  final DateTime reference = now ?? DateTime.now();
  final DateTime moment =
      DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true).toLocal();
  final Duration diff = reference.difference(moment);
  if (diff.isNegative) return 'en el futuro';
  final int seconds = diff.inSeconds;
  if (seconds < 60) return 'hace unos segundos';
  final int minutes = diff.inMinutes;
  if (minutes < 60) return 'hace $minutes min';
  final int hours = diff.inHours;
  if (hours < 24) return 'hace $hours h';
  final int days = diff.inDays;
  if (days < 30) return 'hace $days d';
  final int months = days ~/ 30;
  if (months < 12) return 'hace $months mes${months == 1 ? '' : 'es'}';
  final int years = days ~/ 365;
  return 'hace $years año${years == 1 ? '' : 's'}';
}

/// Clasifica la actividad a partir de los minutos recientes sumados.
///
/// Devuelve `null` si los minutos no se conocen: sin una respuesta válida de
/// Steam no se debe asignar un nivel como si fuese una medición.
///
/// - `none`: cero minutos comunicados.
/// - `low`: inferior al umbral moderado.
/// - `moderate`: desde el umbral moderado hasta antes del umbral alto.
/// - `high`: igual o superior al umbral alto.
ActivityLevel? classifyActivityMinutes(
  int? recentMinutes, {
  required int moderateThreshold,
  required int highThreshold,
}) {
  if (recentMinutes == null) return null;
  final int moderate = moderateThreshold;
  final int high = highThreshold > moderate ? highThreshold : moderate + 1;
  if (recentMinutes <= 0) return ActivityLevel.none;
  if (recentMinutes >= high) return ActivityLevel.high;
  if (recentMinutes >= moderate) return ActivityLevel.moderate;
  return ActivityLevel.low;
}

/// Clasifica la actividad de un perfil usando los umbrales de sus preferencias.
ActivityLevel? activityLevelFor(ProfileActivity activity, Preferences prefs) =>
    classifyActivityMinutes(
      activity.totalRecentMinutes,
      moderateThreshold: prefs.moderateActivityMinutes,
      highThreshold: prefs.highActivityMinutes,
    );

/// Etiqueta legible del nivel de actividad.
String describeActivityLevel(ActivityLevel? level) => switch (level) {
      ActivityLevel.none => 'Sin actividad registrada',
      ActivityLevel.low => 'Actividad baja',
      ActivityLevel.moderate => 'Actividad moderada',
      ActivityLevel.high => 'Actividad alta',
      null => 'Actividad no determinada',
    };

/// Mensaje en español para cada estado de consulta.
String describeFetchStatus(FetchStatus status) => switch (status) {
      FetchStatus.notFetched => 'Pendiente de consultar',
      FetchStatus.ok => 'Datos recientes disponibles',
      FetchStatus.noRecentGames =>
        'Steam no comunica juegos en las últimas dos semanas',
      FetchStatus.privateOrUnavailable =>
        'El perfil es privado o sus datos no están disponibles',
      FetchStatus.networkError => 'Sin conexión con Steam',
      FetchStatus.invalidApiKey => 'Clave de Steam Web API no válida',
      FetchStatus.invalidProfile => 'Perfil no encontrado o no válido',
      FetchStatus.rateLimited => 'Steam ha limitado las solicitudes',
      FetchStatus.malformedResponse =>
        'Steam devolvió una respuesta con un formato inesperado',
      FetchStatus.incompleteConfiguration =>
        'Falta configurar la clave de Steam Web API',
    };

/// Aclaración adicional (más larga) para estados que suelen confundirse.
String explainFetchStatus(FetchStatus status) => switch (status) {
      FetchStatus.noRecentGames =>
        'Una respuesta válida sin juegos recientes no significa que el perfil '
            'no haya jugado nunca: solo indica lo que Steam comunica sobre las '
            'últimas dos semanas.',
      FetchStatus.privateOrUnavailable =>
        'Steam no ha entregado los datos. Puede deberse a la configuración de '
            'privacidad del perfil ("Detalles del juego" restringidos) o a que '
            'el perfil no existe.',
      FetchStatus.invalidApiKey =>
        'Steam ha rechazado la clave. Comprueba la clave configurada en Ajustes.',
      FetchStatus.rateLimited =>
        'Steam ha devuelto un error 429. Espera antes de volver a intentarlo.',
      FetchStatus.networkError =>
        'Se muestra la última información disponible, procedente de la caché local.',
      _ => '',
    };

/// Color (en formato `0xAARRGGBB`) asociado a un nivel de actividad.
int activityLevelColorValue(ActivityLevel? level) => switch (level) {
      ActivityLevel.high => 0xFFE06C75,
      ActivityLevel.moderate => 0xFFE0B341,
      ActivityLevel.low => 0xFF7BC96F,
      ActivityLevel.none => 0xFF9BA1B0,
      null => 0xFF9BA1B0,
    };

/// Etiqueta de una consulta antigua, usada cuando se muestra la caché.
String describeCacheOrigin({
  required bool fromCache,
  required bool isStale,
  required int? lastSuccessAtUnix,
}) {
  if (!fromCache && !isStale) return 'Actualizado';
  final String when = formatRelativeTime(lastSuccessAtUnix);
  if (isStale) return 'Caché desactualizada ($when)';
  return 'Desde caché ($when)';
}

/// Comprueba si una marca de tiempo es más antigua que [AppConstants.staleAfter].
bool isStaleTimestamp(int? lastSuccessAtUnix, {DateTime? now}) {
  if (lastSuccessAtUnix == null || lastSuccessAtUnix <= 0) return true;
  final DateTime reference = now ?? DateTime.now();
  final DateTime moment = DateTime.fromMillisecondsSinceEpoch(
    lastSuccessAtUnix * 1000,
    isUtc: true,
  );
  return reference.difference(moment) > AppConstants.staleAfter;
}
