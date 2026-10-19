/// Lectura del XML público de perfil de Steam Community.
///
/// Steam Community publica el XML **oficial** de un perfil en
/// `https://steamcommunity.com/profiles/{id}?xml=1` (y en
/// `/id/{nombre}?xml=1`) sin necesidad de ninguna credencial. WATAP lo usa
/// **únicamente cuando no hay clave de Web API** para obtener el nombre, el
/// avatar y la visibilidad: son datos estructurados de un endpoint público,
/// **nunca se analiza HTML** (no hay *scraping*).
///
/// Parseo defensivo con `package:xml`:
/// - `<response><error>…</error></response>` → el perfil no existe.
/// - Cualquier XML inesperado → `malformed`, nunca una excepción sin capturar.
///
/// Funciones puras, probadas en `test/data/community_profile_parser_test.dart`.
library;

import 'package:xml/xml.dart';

import '../../core/models.dart';

/// Perfil público leído del XML de Steam Community.
class CommunityProfile {
  const CommunityProfile({
    this.steamId64,
    this.personaName,
    this.avatarUrl,
    this.communityVisibilityState,
  });

  final String? steamId64;
  final String? personaName;
  final String? avatarUrl;

  /// 1 = privado, 2 = solo amigos, 3 = público (mismo significado que
  /// `communityvisibilitystate` de `GetPlayerSummaries`).
  final int? communityVisibilityState;

  /// Convierte al mismo modelo que produce `GetPlayerSummaries`, de modo que
  /// los dos caminos (clave y XML) sean indistinguibles para el resto de la app.
  ///
  /// [fallbackSteamId64] es el identificador consultado, por si el XML no lo
  /// trajera (se pidió por esa vía, así que es válido).
  SteamPlayerSummary toSummary(String fallbackSteamId64) => SteamPlayerSummary(
        steamId64: steamId64 ?? fallbackSteamId64,
        personaName: personaName,
        avatarUrl: avatarUrl,
        communityVisibilityState: communityVisibilityState,
      );
}

/// Estado defensivo del parseo del XML de perfil.
enum CommunityProfileParseStatus {
  /// Perfil leído correctamente.
  ok,

  /// Steam respondió `<error>`: el perfil no existe.
  notFound,

  /// XML vacío, malformado o sin identidad de perfil.
  malformed,
}

/// Resultado del parseo: nunca lanza excepciones.
class CommunityProfileParseResult {
  const CommunityProfileParseResult._(this.status, this.profile);

  const CommunityProfileParseResult.ok(CommunityProfile profile)
      : this._(CommunityProfileParseStatus.ok, profile);

  const CommunityProfileParseResult.notFound()
      : this._(CommunityProfileParseStatus.notFound, null);

  const CommunityProfileParseResult.malformed()
      : this._(CommunityProfileParseStatus.malformed, null);

  final CommunityProfileParseStatus status;
  final CommunityProfile? profile;
}

/// Analiza el cuerpo XML de un perfil público.
///
/// Los valores de Steam llegan como texto plano o envueltos en `<![CDATA[…]]>`;
/// `XmlElement.innerText` devuelve ambos casos de forma uniforme.
CommunityProfileParseResult parseCommunityProfile(String body) {
  if (body.trim().isEmpty) {
    return const CommunityProfileParseResult.malformed();
  }

  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } catch (_) {
    // Cualquier error de sintaxis: respuesta inesperada, no un perfil.
    return const CommunityProfileParseResult.malformed();
  }

  // Steam indica "perfil no existe" con <response><error>…</error></response>.
  if (document.findAllElements('error').isNotEmpty) {
    return const CommunityProfileParseResult.notFound();
  }

  final XmlElement root = document.rootElement;
  if (root.name.local != 'profile') {
    return const CommunityProfileParseResult.malformed();
  }

  final String? steamId64 = _text(root, 'steamID64');
  final String? personaName = _text(root, 'steamID');

  // Sin ninguna identidad, el documento no sirve como perfil.
  if (steamId64 == null && personaName == null) {
    return const CommunityProfileParseResult.malformed();
  }

  return CommunityProfileParseResult.ok(
    CommunityProfile(
      steamId64: steamId64,
      personaName: personaName,
      // avatarFull → avatarMedium: cualquiera sirve; nunca inventar.
      avatarUrl: _text(root, 'avatarFull') ?? _text(root, 'avatarMedium'),
      communityVisibilityState: _visibility(root),
    ),
  );
}

/// Primer hijo directo no vacío con ese nombre.
String? _text(XmlElement root, String name) {
  final String? value = root.getElement(name)?.innerText.trim();
  return (value == null || value.isEmpty) ? null : value;
}

/// Visibilidad del perfil, con el mismo significado numérico que la Web API.
int? _visibility(XmlElement root) {
  final String? raw = _text(root, 'visibilityState');
  final int? fromNumber = raw == null ? null : int.tryParse(raw);
  if (fromNumber != null) return fromNumber;

  // Respaldo con el texto de privacidad, por si trae el número ausente.
  return switch (_text(root, 'privacyState')) {
    'public' => 3,
    'friendsonly' => 2,
    'private' => 1,
    _ => null,
  };
}
