/// Pruebas de los datos de demostración.
///
/// Verifican que todo lo ficticio esté marcado como tal y que los
/// identificadores reservados se reconozcan siempre.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/constants.dart';
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/steam/steam_api_urls.dart';
import 'package:watap_mobile/services/demo_data.dart';

void main() {
  test('los perfiles de demostración son ficticios y están marcados', () {
    final List<Profile> profiles = DemoData.profiles(createdAtUnix: 100);
    expect(profiles, hasLength(AppConstants.demoSteamId64s.length));
    for (final Profile profile in profiles) {
      expect(profile.isDemo, isTrue);
      expect(AppConstants.demoSteamId64s, contains(profile.steamId64));
      expect(profile.displayName, contains('demostración'));
    }
    expect(
      profiles.map((Profile p) => p.steamId64).toSet(),
      AppConstants.demoSteamId64s.toSet(),
    );
  });

  test('los identificadores reservados se reconocen', () {
    for (final String id in AppConstants.demoSteamId64s) {
      expect(DemoData.isDemoSteamId(id), isTrue);
      expect(DemoData.looksLikeDemo(id), isTrue);
    }
    expect(DemoData.isDemoSteamId('76561198000000000'), isFalse);
    expect(DemoData.looksLikeDemo('76561198000000000'), isFalse);
  });

  test('las actividades y los juegos van marcados como demostración', () {
    const int now = 1700000000;
    final List<ProfileActivity> activities = DemoData.activityList(nowUnix: now);
    expect(activities, hasLength(AppConstants.demoSteamId64s.length));
    for (final ProfileActivity activity in activities) {
      expect(activity.isDemo, isTrue);
      expect(activity.status, FetchStatus.ok);
      expect(activity.games, isNotEmpty);
      for (final Game game in activity.games) {
        expect(game.isDemo, isTrue);
        expect(game.coverUrl, SteamApiUrls.gameCover(game.appId).toString());
      }
    }
  });

  test('activityFor devuelve la actividad del perfil y null para otros', () {
    final ProfileActivity? hay = DemoData.activityFor(AppConstants.demoSteamId64s.first);
    expect(hay, isNotNull);
    expect(hay!.steamId64, AppConstants.demoSteamId64s.first);
    expect(DemoData.activityFor('76561198000000000'), isNull);
  });

  test('los avisos dejan claro que los datos son ficticios', () {
    expect(DemoData.notice, contains('DEMOSTRACIÓN'));
    expect(DemoData.shortNotice, contains('DEMOSTRACIÓN'));
  });
}
