/// Pruebas del parseo defensivo de respuestas de la Steam Web API.
///
/// Todas las respuestas son ficticias: la suite nunca consulta Steam.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/steam/steam_api_errors.dart';
import 'package:watap_mobile/data/steam/steam_api_urls.dart';
import 'package:watap_mobile/data/steam/steam_json_parsers.dart';

void main() {
  group('parseRecentlyPlayedGames', () {
    test('una respuesta vacía NO significa "cero juegos"', () {
      final RecentlyPlayedParseResult result =
          parseRecentlyPlayedGames('{"response":{}}');
      expect(result.responsePresent, isFalse);
      expect(result.isUsable, isFalse);
      expect(result.games, isEmpty);
    });

    test('una respuesta válida sin juegos sí expresa cero', () {
      final RecentlyPlayedParseResult result =
          parseRecentlyPlayedGames('{"response":{"total_count":0,"games":[]}}');
      expect(result.responsePresent, isTrue);
      expect(result.totalCount, 0);
      expect(result.games, isEmpty);
      expect(result.isUsable, isTrue);
    });

    test('parsea juegos, satura negativos y calcula recursos', () {
      const String body = '''
      {
        "response": {
          "total_count": 2,
          "games": [
            {"appid": 620, "name": "Portal 2", "playtime_2weeks": 30,
             "playtime_forever": -10, "img_icon_url": "hash620"},
            {"appid": 570, "name": "Dota 2", "playtime_2weeks": 100,
             "img_icon_url": "hash570"}
          ]
        }
      }
      ''';
      final RecentlyPlayedParseResult result = parseRecentlyPlayedGames(body);
      expect(result.games, hasLength(2));
      // Se ordenan por tiempo reciente descendente.
      expect(result.games.first.appId, 570);
      final Game portal = result.games.last;
      expect(portal.playtime2Weeks, 30);
      expect(portal.playtimeForever, 0);
      expect(portal.iconUrl, SteamApiUrls.gameIcon(620, 'hash620').toString());
      expect(result.games.first.iconUrl, SteamApiUrls.gameIcon(570, 'hash570').toString());
    });

    test('descarta entradas sin AppID válido', () {
      final RecentlyPlayedParseResult result = parseRecentlyPlayedGames(
        '{"response":{"games":[{"name":"Sin id"},{"appid":0,"name":"Cero"}]}}',
      );
      expect(result.games, isEmpty);
      expect(result.responsePresent, isTrue);
    });

    test('un JSON inválido lanza malformedResponse', () {
      expect(
        () => parseRecentlyPlayedGames('{esto no es json}'),
        throwsA(
          isA<SteamApiException>()
              .having((SteamApiException e) => e.kind, 'kind', SteamApiErrorKind.malformedResponse),
        ),
      );
    });

    test('un cuerpo vacío lanza malformedResponse', () {
      expect(
        () => parseRecentlyPlayedGames('   '),
        throwsA(isA<SteamApiException>()),
      );
    });

    test('un JSON que no es objeto lanza malformedResponse', () {
      expect(
        () => parseRecentlyPlayedGames('[1,2,3]'),
        throwsA(
          isA<SteamApiException>()
              .having((SteamApiException e) => e.kind, 'kind', SteamApiErrorKind.malformedResponse),
        ),
      );
    });
  });

  group('parsePlayerSummaries', () {
    test('conserva solo perfiles con SteamID64 válido', () {
      const String body = '''
      {
        "response": {
          "players": [
            {"steamid": "76561198000000000", "personaname": "Ana",
             "avatarfull": "https://x/ana.jpg", "communityvisibilitystate": 3},
            {"steamid": "123", "personaname": "Corto"},
            {"steamid": "76561198000000009", "personaname": "Bruno",
             "communityvisibilitystate": 1, "personastate": 0}
          ]
        }
      }
      ''';
      final List<SteamPlayerSummary> players = parsePlayerSummaries(body);
      expect(players, hasLength(2));
      expect(players.first.steamId64, '76561198000000000');
      expect(players.first.avatarUrl, 'https://x/ana.jpg');
      expect(players.first.isPublicProfile, isTrue);
      expect(players.last.isPublicProfile, isFalse);
    });

    test('una lista vacía es una respuesta válida sin perfiles', () {
      expect(parsePlayerSummaries('{"response":{"players":[]}}'), isEmpty);
    });
  });

  group('parseVanityResolution', () {
    test('success 1 devuelve el SteamID64', () {
      final VanityResolution result = parseVanityResolution(
        '{"response":{"success":1,"steamid":"76561198000000000"}}',
      );
      expect(result.success, isTrue);
      expect(result.steamId64, '76561198000000000');
    });

    test('success 42 informa de que el nombre no existe', () {
      final VanityResolution result =
          parseVanityResolution('{"response":{"success":42,"message":"No match"}}');
      expect(result.success, isFalse);
      expect(result.messageEs, contains('No existe'));
    });

    test('un success distinto se traduce a un mensaje claro', () {
      final VanityResolution result =
          parseVanityResolution('{"response":{"success":7}}');
      expect(result.success, isFalse);
      expect(result.messageEs, isNotEmpty);
    });
  });

  group('parseFamilyGroupForUser', () {
    test('detecta el grupo familiar de la cuenta', () {
      const String body = '''
      {
        "response": {
          "family_groupid": "123456789",
          "is_not_member_of_any_group": false
        }
      }
      ''';
      final FamilyGroupForUser result = parseFamilyGroupForUser(body);
      expect(result.hasGroup, isTrue);
      expect(result.familyGroupId, '123456789');
    });

    test('la cuenta sin grupo se indica como tal', () {
      const String body = '{"response":{"is_not_member_of_any_group":true}}';
      final FamilyGroupForUser result = parseFamilyGroupForUser(body);
      expect(result.hasGroup, isFalse);
      expect(result.familyGroupId, isNull);
    });
  });

  group('parseFamilyGroup', () {
    test('extrae el nombre y los integrantes', () {
      const String body = '''
      {
        "response": {
          "name": "Familia de prueba",
          "members": [
            {"steamid": "76561198000000000", "role": 1, "time_joined": 1700000000},
            {"steamid": "76561198000000000"},
            {"steamid": "abc"},
            {"steamid": "76561198000000009", "role": 0}
          ],
          "free_spots": 2
        }
      }
      ''';
      final FamilyGroup group = parseFamilyGroup(
        body,
        familyGroupId: '123456789',
      );
      expect(group.name, 'Familia de prueba');
      expect(group.members, hasLength(2));
      expect(group.memberSteamIds, <String>[
        '76561198000000000',
        '76561198000000009',
      ]);
      expect(group.members.first.role, 1);
      expect(group.members.first.timeJoinedUnix, 1700000000);
      expect(group.members.last.role, 0);
      expect(group.freeSpots, 2);
    });

    test('una respuesta vacía da un grupo sin integrantes', () {
      final FamilyGroup group = parseFamilyGroup('{}', familyGroupId: 'x');
      expect(group.members, isEmpty);
      expect(group.name, isNull);
    });
  });
}
