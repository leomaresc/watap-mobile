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
}