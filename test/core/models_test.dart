/// Pruebas de los modelos de dominio, incluidas las reglas de datos
/// desconocidos (que nunca deben convertirse en ceros engañosos).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/models.dart';

void main() {
  group('Profile', () {
    test('displayName prioriza alias, luego personaName y luego el ID', () {
      const Profile withAlias = Profile(
        steamId64: '76561198000000000',
        personaName: 'Nombre Público',
        alias: 'Alias local',
        createdAtUnix: 1,
      );
      expect(withAlias.displayName, 'Alias local');

      const Profile noAlias = Profile(
        steamId64: '76561198000000000',
        personaName: 'Nombre Público',
        createdAtUnix: 1,
      );
      expect(noAlias.displayName, 'Nombre Público');

      const Profile bare = Profile(steamId64: '76561198000000000', createdAtUnix: 1);
      expect(bare.displayName, 'Perfil 76561198000000000');
    });

    test('la marca de demostración sobrevive al viaje por mapa', () {
      const Profile profile = Profile(
        steamId64: '90000000000000001',
        personaName: 'DEMO - Ana',
        isDemo: true,
        createdAtUnix: 7,
      );
      final Map<String, Object?> map = profile.toMap();
      expect(map['is_demo'], 1);
      final Profile restored = Profile.fromMap(map);
      expect(restored.isDemo, isTrue);
      expect(restored.steamId64, profile.steamId64);
      expect(restored.personaName, profile.personaName);
    });

    test('copyWith puede borrar el alias de forma explícita', () {
      const Profile profile = Profile(
        steamId64: '76561198000000000',
        alias: 'Alias',
        createdAtUnix: 1,
      );
      expect(profile.copyWith(clearAlias: true).alias, isNull);
      expect(profile.copyWith(alias: 'Otro').alias, 'Otro');
    });
  });

  group('Game', () {
    test('un tiempo acumulado desconocido se conserva como null', () {
      final Game game = Game.fromMap(<String, Object?>{
        'app_id': 570,
        'name': 'Dota 2',
        'playtime_2weeks': 100,
        'playtime_forever': null,
      });
      expect(game.playtimeForever, isNull);
      expect(game.hasPlaytimeForever, isFalse);
    });

    test('los minutos negativos se saturan a cero', () {
      final Game game = Game.fromMap(<String, Object?>{
        'app_id': 570,
        'playtime_2weeks': -50,
        'playtime_forever': -10,
      });
      expect(game.playtime2Weeks, 0);
      expect(game.playtimeForever, 0);
    });

    test('label usa el AppID cuando falta el nombre', () {
      const Game game = Game(appId: 123);
      expect(game.label, 'AppID 123');
    });
  });

  group('ProfileActivity', () {
    test('los totales son null cuando Steam no respondió', () {
      const ProfileActivity failed = ProfileActivity(
        steamId64: '76561198000000000',
        status: FetchStatus.networkError,
        games: <Game>[Game(appId: 570, playtime2Weeks: 100)],
      );
      expect(failed.totalRecentMinutes, isNull);
      expect(failed.totalForeverMinutes, isNull);
    });

    test('una respuesta válida sin juegos da cero, no null', () {
      const ProfileActivity empty = ProfileActivity(
        steamId64: '76561198000000000',
        status: FetchStatus.noRecentGames,
      );
      expect(empty.totalRecentMinutes, 0);
      expect(empty.totalForeverMinutes, 0);
    });

    test('el acumulado parcial se marca como incompleto', () {
      const ProfileActivity partial = ProfileActivity(
        steamId64: '76561198000000000',
        status: FetchStatus.ok,
        games: <Game>[
          Game(appId: 570, playtime2Weeks: 100, playtimeForever: 1000),
          Game(appId: 620, playtime2Weeks: 50),
        ],
      );
      expect(partial.totalRecentMinutes, 150);
      expect(partial.totalForeverMinutes, isNull);
      expect(partial.hasCompleteForever, isFalse);
    });

    test('el acumulado completo suma todos los juegos', () {
      const ProfileActivity complete = ProfileActivity(
        steamId64: '76561198000000000',
        status: FetchStatus.ok,
        games: <Game>[
          Game(appId: 570, playtime2Weeks: 100, playtimeForever: 1000),
          Game(appId: 620, playtime2Weeks: 50, playtimeForever: 500),
        ],
      );
      expect(complete.totalForeverMinutes, 1500);
      expect(complete.hasCompleteForever, isTrue);
    });
  });

  group('Preferences', () {
    test('los valores por defecto son coherentes', () {
      const Preferences defaults = Preferences.defaults();
      expect(defaults.moderateActivityMinutes, 120);
      expect(defaults.highActivityMinutes, 480);
      expect(defaults.lowActivityFilterMinutes, 30);
      expect(defaults.demoModeEnabled, isFalse);
    });

    test('sanitized corrige umbrales invertidos', () {
      final Preferences pref = const Preferences.defaults()
          .copyWith(moderateActivityMinutes: 600, highActivityMinutes: 100)
          .sanitized();
      expect(pref.moderateActivityMinutes, 600);
      expect(pref.highActivityMinutes, 601);
    });

    test('sanitized impide que el filtro bajo supere al moderado', () {
      final Preferences pref = const Preferences.defaults()
          .copyWith(
            lowActivityFilterMinutes: 5000,
            moderateActivityMinutes: 120,
            highActivityMinutes: 480,
          )
          .sanitized();
      expect(pref.lowActivityFilterMinutes, 120);
    });

    test('el viaje por clave/valor conserva lo importante', () {
      final Preferences original = const Preferences.defaults().copyWith(
        hideLowActivity: true,
        showCovers: false,
        moderateActivityMinutes: 200,
        highActivityMinutes: 400,
        lastSelectedProfile: '76561198000000000',
        lastSection: 'overview',
        demoModeEnabled: true,
      );
      final Preferences restored =
          Preferences.fromKeyValueMap(original.toKeyValueMap());
      expect(restored.hideLowActivity, isTrue);
      expect(restored.showCovers, isFalse);
      expect(restored.moderateActivityMinutes, 200);
      expect(restored.highActivityMinutes, 400);
      expect(restored.lastSelectedProfile, '76561198000000000');
      expect(restored.lastSection, 'overview');
      expect(restored.demoModeEnabled, isTrue);
    });

    test('un mapa vacío devuelve los valores por defecto', () {
      final Preferences restored =
          Preferences.fromKeyValueMap(const <String, String>{});
      expect(restored.moderateActivityMinutes, 120);
      expect(restored.highActivityMinutes, 480);
      expect(restored.lastSelectedProfile, isNull);
    });
  });
}
