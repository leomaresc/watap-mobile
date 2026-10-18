/// Datos ficticios del modo demostración.
///
/// Todo el contenido de este archivo es inventado y tiene finalidad
/// exclusivamente demostrativa:
/// - Los SteamID64 son reservados y **nunca** se envían a Steam.
/// - Los nombres de juego son reales (para que las portadas del CDN público
///   puedan mostrarse), pero los tiempos son ficticios.
/// - Cada perfil y cada actividad llevan `isDemo = true`, de modo que la
///   interfaz puede marcarlos de forma inequívoca y persistente.
///
/// Se prueban en `test/services/demo_data_test.dart`.
library;

import '../core/constants.dart';
import '../core/models.dart';
import '../data/steam/steam_api_urls.dart';

/// Generador de los datos de demostración.
class DemoData {
  const DemoData._();

  /// Aviso que debe mostrarse mientras haya datos de demostración en pantalla.
  static const String notice =
      'Estás viendo datos de DEMOSTRACIÓN. Son ficticios y no proceden de Steam.';

  /// Aviso más corto para la cabecera.
  static const String shortNotice = 'DEMOSTRACIÓN · datos ficticios';

  /// `true` si el identificador pertenece al conjunto de demostración.
  static bool isDemoSteamId(String steamId64) =>
      AppConstants.demoSteamId64s.contains(steamId64.trim());

  /// Identificador reservado de un perfil de demostración.
  static bool looksLikeDemo(String value) =>
      value.trim().startsWith('900000000000');

  static const int _dota2 = 570;
  static const int _stardew = 413150;
  static const int _valheim = 892970;
  static const int _cs2 = 730;
  static const int _eldenRing = 1245620;
  static const int _portal2 = 620;

  /// Perfiles de demostración, en el orden en que se muestran.
  static List<Profile> profiles({int? createdAtUnix}) {
    final int created = createdAtUnix ?? 0;
    return <Profile>[
      Profile(
        steamId64: AppConstants.demoSteamId64s[0],
        personaName: 'DEMO - Ana',
        alias: 'Ana (demostración)',
        avatarUrl: null,
        isDemo: true,
        createdAtUnix: created,
      ),
      Profile(
        steamId64: AppConstants.demoSteamId64s[1],
        personaName: 'DEMO - Bruno',
        alias: 'Bruno (demostración)',
        avatarUrl: null,
        isDemo: true,
        createdAtUnix: created + 1,
      ),
      Profile(
        steamId64: AppConstants.demoSteamId64s[2],
        personaName: 'DEMO - Carla',
        alias: 'Carla (demostración)',
        avatarUrl: null,
        isDemo: true,
        createdAtUnix: created + 2,
      ),
    ];
  }

  /// Actividades de demostración, indexadas por SteamID64.
  static Map<String, ProfileActivity> activities({int? nowUnix}) {
    final int now = nowUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final Map<String, ProfileActivity> map = <String, ProfileActivity>{};
    for (final ProfileActivity activity in activityList(nowUnix: now)) {
      map[activity.steamId64] = activity;
    }
    return map;
  }

  /// Lista de actividades de demostración.
  static List<ProfileActivity> activityList({int? nowUnix}) {
    final int now = nowUnix ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return <ProfileActivity>[
      ProfileActivity(
        steamId64: AppConstants.demoSteamId64s[0],
        personaName: 'DEMO - Ana',
        games: const <Game>[
          Game(
            appId: _dota2,
            name: 'Dota 2',
            playtime2Weeks: 620,
            playtimeForever: 41230,
            isDemo: true,
          ),
          Game(
            appId: _stardew,
            name: 'Stardew Valley',
            playtime2Weeks: 340,
            playtimeForever: 8120,
            isDemo: true,
          ),
          Game(
            appId: _valheim,
            name: 'Valheim',
            playtime2Weeks: 90,
            playtimeForever: 2450,
            isDemo: true,
          ),
        ].map(_withCover).toList(growable: false),
        status: FetchStatus.ok,
        statusMessage: 'Datos de demostración (ficticios).',
        fetchedAtUnix: now - 300,
        lastSuccessAtUnix: now - 300,
        isDemo: true,
      ),
      ProfileActivity(
        steamId64: AppConstants.demoSteamId64s[1],
        personaName: 'DEMO - Bruno',
        games: const <Game>[
          Game(
            appId: _cs2,
            name: 'Counter-Strike 2',
            playtime2Weeks: 780,
            playtimeForever: 98760,
            isDemo: true,
          ),
          Game(
            appId: _dota2,
            name: 'Dota 2',
            playtime2Weeks: 210,
            playtimeForever: 33210,
            isDemo: true,
          ),
          Game(
            appId: _eldenRing,
            name: 'ELDEN RING',
            playtime2Weeks: 55,
            playtimeForever: 5120,
            isDemo: true,
          ),
        ].map(_withCover).toList(growable: false),
        status: FetchStatus.ok,
        statusMessage: 'Datos de demostración (ficticios).',
        fetchedAtUnix: now - 900,
        lastSuccessAtUnix: now - 900,
        isDemo: true,
      ),
      ProfileActivity(
        steamId64: AppConstants.demoSteamId64s[2],
        personaName: 'DEMO - Carla',
        games: const <Game>[
          Game(
            appId: _stardew,
            name: 'Stardew Valley',
            playtime2Weeks: 480,
            playtimeForever: 15400,
            isDemo: true,
          ),
          Game(
            appId: _portal2,
            name: 'Portal 2',
            playtime2Weeks: 45,
            playtimeForever: 980,
            isDemo: true,
          ),
        ].map(_withCover).toList(growable: false),
        status: FetchStatus.ok,
        statusMessage: 'Datos de demostración (ficticios).',
        fetchedAtUnix: now - 7200,
        lastSuccessAtUnix: now - 7200,
        isDemo: true,
      ),
    ];
  }

  /// Actividad concreta de un perfil de demostración.
  static ProfileActivity? activityFor(String steamId64, {int? nowUnix}) {
    for (final ProfileActivity activity in activityList(nowUnix: nowUnix)) {
      if (activity.steamId64 == steamId64) return activity;
    }
    return null;
  }

  /// Añade la portada del CDN público de Steam, calculada a partir del AppID.
  ///
  /// No se realiza ninguna solicitud de red aquí: solo se construye la URL.
  static Game _withCover(Game game) => game.copyWith(
        coverUrl: SteamApiUrls.gameCover(game.appId).toString(),
      );
}
