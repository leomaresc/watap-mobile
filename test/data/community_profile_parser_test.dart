/// Pruebas del parser del XML público de perfil de Steam Community.
///
/// Es la fuente de nombre, avatar y visibilidad cuando no hay clave de Web
/// API. Ninguna prueba toca la red: se leen cuerpos fijos, incluidos los casos
/// reales de Steam (`<![CDATA[…]]>` y `<response><error>…</error></response>`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/data/steam/community_profile_parser.dart';

import '../helpers/test_support.dart';

void main() {
  group('parseCommunityProfile', () {
    test('lee un perfil público con CDATA, avatar y visibilidad', () {
      final CommunityProfileParseResult result =
          parseCommunityProfile(communityProfileXmlBody());

      expect(result.status, CommunityProfileParseStatus.ok);
      final CommunityProfile profile = result.profile!;
      expect(profile.steamId64, '76561198000000000');
      expect(profile.personaName, 'Ana');
      expect(profile.avatarUrl, 'https://avatars.example/anafull.jpg');
      expect(profile.communityVisibilityState, 3);
    });

    test('sin visibilityState usa privacyState como respaldo', () {
      const String body =
          '<?xml version="1.0"?><profile>'
          '<steamID64>76561198000000000</steamID64>'
          '<steamID><![CDATA[Ana]]></steamID>'
          '<privacyState>friendsonly</privacyState>'
          '</profile>';

      final CommunityProfileParseResult result = parseCommunityProfile(body);

      expect(result.status, CommunityProfileParseStatus.ok);
      expect(result.profile!.communityVisibilityState, 2);
    });

    test('un perfil privado conserva su visibilidad', () {
      final CommunityProfileParseResult result = parseCommunityProfile(
        communityProfileXmlBody(visibilityState: 1, privacyState: 'private'),
      );

      expect(result.status, CommunityProfileParseStatus.ok);
      expect(result.profile!.communityVisibilityState, 1);
    });

    test('un avatar ausente no inventa ninguno', () {
      final CommunityProfileParseResult result = parseCommunityProfile(
        communityProfileXmlBody(avatarUrl: null),
      );

      expect(result.status, CommunityProfileParseStatus.ok);
      expect(result.profile!.avatarUrl, isNull);
    });

    test('la respuesta de perfil inexistente se detecta como notFound', () {
      final CommunityProfileParseResult result =
          parseCommunityProfile(communityProfileNotFoundXml);

      expect(result.status, CommunityProfileParseStatus.notFound);
      expect(result.profile, isNull);
    });

    test('un cuerpo vacío o malformado es malformed, nunca excepción', () {
      expect(
        parseCommunityProfile('').status,
        CommunityProfileParseStatus.malformed,
      );
      expect(
        parseCommunityProfile('<html>no soy xml</html>').status,
        CommunityProfileParseStatus.malformed,
      );
      expect(
        parseCommunityProfile('<?xml version="1.0"?><otra/>').status,
        CommunityProfileParseStatus.malformed,
      );
    });

    test('un perfil sin identidad alguna es malformed', () {
      const String body = '<?xml version="1.0"?><profile></profile>';

      expect(
        parseCommunityProfile(body).status,
        CommunityProfileParseStatus.malformed,
      );
    });
  });

  group('toSummary', () {
    test('produce el mismo modelo que GetPlayerSummaries', () {
      final CommunityProfile profile =
          parseCommunityProfile(communityProfileXmlBody()).profile!;

      expect(
        profile.toSummary('otro-id').steamId64,
        '76561198000000000',
        reason: 'El identificador del XML manda sobre el consultado.',
      );
    });

    test('usa el consultado si el XML no trae el identificador', () {
      const CommunityProfile profile = CommunityProfile(personaName: 'Ana');

      expect(profile.toSummary('76561198000000042').steamId64,
          '76561198000000042');
      expect(profile.toSummary('x').personaName, 'Ana');
    });
  });
}
