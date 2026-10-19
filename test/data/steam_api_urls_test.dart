/// Pruebas de construcción de URLs.
///
/// El punto más importante: **ninguna URL contiene una credencial por sí
/// misma**. El `access_token` lo añade el cliente únicamente para
/// `api.steampowered.com` (ver `steam_api_client_test.dart`); las URLs del XML
/// público de Steam Community se emiten siempre sin credencial.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/constants.dart';
import 'package:watap_mobile/data/steam/steam_api_urls.dart';

void main() {
  group('recentlyPlayed', () {
    test('incluye steamid, formato e info de la app', () {
      final Uri uri = SteamApiUrls.recentlyPlayed('76561198000000000');
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.steampowered.com');
      expect(uri.path, SteamApiEndpoints.recentlyPlayed);
      expect(uri.queryParameters['steamid'], '76561198000000000');
      expect(uri.queryParameters['include_appinfo'], '1');
      expect(uri.queryParameters['format'], 'json');
    });

    test('nunca incluye una credencial por sí misma', () {
      final Uri uri = SteamApiUrls.recentlyPlayed('76561198000000000');
      expect(uri.queryParameters.containsKey('key'), isFalse);
      expect(uri.queryParameters.containsKey('access_token'), isFalse);
    });
  });

  group('grupo familiar', () {
    test('familyGroupForUser lleva el token como access_token en GET', () {
      final Uri uri = SteamApiUrls.familyGroupForUser('token-ejemplo');
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.steampowered.com');
      expect(uri.path, SteamApiEndpoints.familyGroupForUser);
      expect(uri.queryParameters['access_token'], 'token-ejemplo');
      expect(uri.queryParameters['format'], 'json');
      expect(uri.queryParameters.containsKey('key'), isFalse);
    });

    test('familyGroup incluye el identificador del grupo', () {
      final Uri uri = SteamApiUrls.familyGroup('token-ejemplo', '42');
      expect(uri.path, SteamApiEndpoints.familyGroup);
      expect(uri.queryParameters['access_token'], 'token-ejemplo');
      expect(uri.queryParameters['family_groupid'], '42');
    });
  });

  group('XML público de perfil (fuente sin credenciales)', () {
    test('communityProfileXml apunta a steamcommunity.com con xml=1', () {
      final Uri uri = SteamApiUrls.communityProfileXml('76561198000000000');
      expect(uri.scheme, 'https');
      expect(uri.host, 'steamcommunity.com');
      expect(uri.path, '/profiles/76561198000000000');
      expect(uri.queryParameters['xml'], '1');
      expect(uri.queryParameters.containsKey('key'), isFalse);
      expect(uri.queryParameters.containsKey('access_token'), isFalse,
          reason: 'El token jamás viaja a steamcommunity.com.');
    });

    test('communityVanityProfileXml usa /id/{nombre} recortado', () {
      final Uri uri = SteamApiUrls.communityVanityProfileXml('  nombre  ');
      expect(uri.scheme, 'https');
      expect(uri.host, 'steamcommunity.com');
      expect(uri.path, '/id/nombre');
      expect(uri.queryParameters['xml'], '1');
      expect(uri.queryParameters.containsKey('access_token'), isFalse);
    });
  });

  group('recursos del CDN', () {
    test('gameCover apunta a la cabecera del AppID', () {
      expect(
        SteamApiUrls.gameCover(570).toString(),
        '${AppConstants.steamCdnBaseUrl}/steam/apps/570/header.jpg',
      );
    });

    test('gameIcon usa el hash del icono', () {
      expect(
        SteamApiUrls.gameIcon(570, 'abc123').toString(),
        '${AppConstants.steamMediaBaseUrl}/570/abc123.jpg',
      );
    });
  });

  group('enlaces externos', () {
    test('storePage, communityProfile y communityVanity', () {
      expect(SteamApiUrls.storePage(570).toString(), 'https://store.steampowered.com/app/570');
      expect(
        SteamApiUrls.communityProfile('76561198000000000').toString(),
        'https://steamcommunity.com/profiles/76561198000000000',
      );
      expect(
        SteamApiUrls.communityVanity('nombre').toString(),
        'https://steamcommunity.com/id/nombre',
      );
    });
  });
}
