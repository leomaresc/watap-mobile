/// Validación y normalización de entradas de perfil.
///
/// Son funciones puras y se prueban en `test/core/validators_test.dart`.
library;

import 'constants.dart';

/// Tipo de entrada reconocida.
enum ProfileInputKind {
  /// SteamID64 de 17 dígitos.
  steamId64,

  /// Nombre personalizado de Steam (URL `/id/{nombre}` o texto suelto).
  vanity,
}

/// Entrada de perfil ya normalizada.
class ParsedProfileInput {
  const ParsedProfileInput({required this.kind, required this.value});

  final ProfileInputKind kind;

  /// SteamID64 o nombre personalizado ya normalizado.
  final String value;

  bool get isSteamId64 => kind == ProfileInputKind.steamId64;
}

/// Resultado del parseo, con mensaje de error en español cuando falla.
class ProfileInputResult {
  const ProfileInputResult._(this.input, this.errorEs);

  factory ProfileInputResult.ok(ParsedProfileInput input) =>
      ProfileInputResult._(input, null);

  factory ProfileInputResult.error(String messageEs) =>
      ProfileInputResult._(null, messageEs);

  final ParsedProfileInput? input;
  final String? errorEs;

  bool get isValid => input != null;
}

/// Expresión de un SteamID64 individual: 17 dígitos.
final RegExp _steamId64Pattern = RegExp(r'^\d{17}$');

/// Nombres personalizados admitidos por Steam: letras, dígitos, `_` y `-`.
final RegExp _vanityPattern = RegExp(r'^[A-Za-z0-9_-]{2,64}$');

/// `true` si la cadena tiene el formato de un SteamID64 (17 dígitos).
///
/// Esto solo valida el **formato**: no confirma que la cuenta exista. La
/// existencia se comprueba consultando la API (`GetPlayerSummaries`).
bool isValidSteamId64(String value) {
  final String v = value.trim();
  if (!_steamId64Pattern.hasMatch(v)) return false;
  // Un identificador todo ceros tiene el formato correcto pero no es una cuenta.
  if (int.tryParse(v) == 0) return false;
  return true;
}

/// Heurística de ayuda: las cuentas personales de Steam empiezan por
/// `7656119`. No se usa para rechazar una entrada, sino para avisar al usuario
/// de que probablemente se trate de un identificador de grupo o de otro tipo.
bool looksLikeIndividualSteamId64(String value) =>
    isValidSteamId64(value) && value.trim().startsWith('7656119');

/// `true` si la cadena es un nombre personalizado válido.
bool isValidVanityName(String value) => _vanityPattern.hasMatch(value.trim());

/// Normaliza espacios y URLs antes de procesar la entrada del usuario.
///
/// Admite:
/// - `76561198000000000`
/// - `https://steamcommunity.com/profiles/76561198000000000`
/// - `https://steamcommunity.com/id/nombrePersonalizado`
/// - `nombrePersonalizado`
/// - `steamcommunity.com/id/nombre` (sin esquema)
String normalizeProfileInput(String raw) {
  String value = raw.trim();
  if (value.isEmpty) return '';
  // Se eliminan los caracteres invisibles más habituales al pegar.
  value = value.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();

  // Se añade el esquema si el usuario pegó la URL sin él.
  final RegExp bareHost = RegExp(r'^(www\.)?steamcommunity\.com/', caseSensitive: false);
  if (bareHost.hasMatch(value)) value = 'https://$value';

  final Uri? uri = Uri.tryParse(value);
  if (uri != null && uri.host.toLowerCase().endsWith('steamcommunity.com')) {
    final List<String> segments =
        uri.pathSegments.where((String s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      final String kind = segments[0].toLowerCase();
      final String id = segments[1].trim();
      if (kind == 'profiles' && isValidSteamId64(id)) return id;
      if (kind == 'id' && isValidVanityName(id)) return id;
    }
    // URL de Steam no reconocida: se devuelve tal cual para que falle con un
    // mensaje explicativo en lugar de interpretarse como un nombre.
    return value;
  }

  // Barra final sobrante en entradas tipo `nombre/`.
  if (value.endsWith('/')) value = value.substring(0, value.length - 1);
  return value;
}

/// Interpreta la entrada del usuario.
///
/// Nunca lanza: devuelve un error legible cuando no puede reconocerla.
ProfileInputResult parseProfileInput(String raw) {
  final String normalized = normalizeProfileInput(raw);
  if (normalized.isEmpty) {
    return ProfileInputResult.error(
      'Introduce un SteamID64, una URL de perfil de Steam o un nombre personalizado.',
    );
  }

  if (isValidSteamId64(normalized)) {
    return ProfileInputResult.ok(
      ParsedProfileInput(kind: ProfileInputKind.steamId64, value: normalized),
    );
  }

  // URL de Steam con formato no reconocido.
  final Uri? uri = Uri.tryParse(normalized);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    if (!uri.host.toLowerCase().endsWith('steamcommunity.com')) {
      return ProfileInputResult.error(
        'Solo se admiten enlaces de steamcommunity.com (perfiles o nombres '
        'personalizados), un SteamID64 o un nombre personalizado.',
      );
    }
    return ProfileInputResult.error(
      'No se ha podido reconocer esa URL. Usa el formato '
      'https://steamcommunity.com/profiles/7656119… o '
      'https://steamcommunity.com/id/nombre.',
    );
  }

  if (_steamId64Pattern.hasMatch(normalized)) {
    // 17 dígitos pero descartado por `isValidSteamId64` (todos ceros).
    return ProfileInputResult.error(
      'Ese SteamID64 no es válido: no puede estar compuesto solo por ceros.',
    );
  }

  if (normalized.contains(' ')) {
    return ProfileInputResult.error(
      'Los nombres personalizados de Steam no contienen espacios. Comprueba el '
      'nombre o pega la URL completa del perfil.',
    );
  }

  if (isValidVanityName(normalized)) {
    return ProfileInputResult.ok(
      ParsedProfileInput(kind: ProfileInputKind.vanity, value: normalized),
    );
  }

  return ProfileInputResult.error(
    'Entrada no válida. Acepta un SteamID64 de 17 dígitos, una URL de perfil '
    'de Steam o un nombre personalizado (letras, números, guion y guion bajo).',
  );
}

/// Valida un alias local. Devuelve un mensaje de error o `null` si es correcto.
String? validateAlias(String? alias) {
  if (alias == null) return null;
  final String value = alias.trim();
  if (value.isEmpty) return null;
  if (value.length > 40) return 'El alias no puede superar los 40 caracteres.';
  return null;
}

/// Valida uno de los umbrales de actividad de los ajustes.
String? validateThreshold(int? value, {required String label, int min = 0}) {
  if (value == null) return 'Introduce un valor para $label.';
  if (value < min) return '$label debe ser igual o superior a $min minutos.';
  if (value > AppConstants.maxActivityThresholdMinutes) {
    return '$label no puede superar ${AppConstants.maxActivityThresholdMinutes} minutos.';
  }
  return null;
}

/// Valida el par de umbrales moderado/alto.
String? validateActivityThresholds(int moderate, int high) {
  if (moderate <= 0) return 'El umbral moderado debe ser mayor que cero.';
  if (high <= moderate) {
    return 'El umbral alto debe ser mayor que el umbral moderado.';
  }
  if (high > AppConstants.maxActivityThresholdMinutes) {
    return 'El umbral alto no puede superar '
        '${AppConstants.maxActivityThresholdMinutes} minutos.';
  }
  return null;
}

/// Valida el formato general de una clave de Steam Web API.
///
/// Steam no documenta la longitud exacta de sus claves, así que solo se
/// comprueban signos evidentes de error (cadena vacía, espacios, longitud
/// absurda). La validez real se determina consultando la API.
String? validateApiKeyFormat(String? key) {
  if (key == null) return null;
  final String value = key.trim();
  if (value.isEmpty) return 'La clave de API no puede estar vacía.';
  if (value.length < 16) return 'La clave parece demasiado corta para ser válida.';
  if (value.length > 128) return 'La clave parece demasiado larga para ser válida.';
  if (value.contains(RegExp(r'\s'))) {
    return 'La clave no debe contener espacios ni saltos de línea.';
  }
  return null;
}

