/// Pruebas de la agregación, el filtrado y la ordenación de la actividad.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/services/activity_aggregator.dart';

ProfileActivity _activity(
  String id,
  List<Game> games, {
  String? name,
  FetchStatus status = FetchStatus.ok,
}) =>
    ProfileActivity(
      steamId64: id,
      personaName: name,
      games: games,
      status: status,
    );

void main() {
  group('sumMinutes y allKnown', () {
    test('sumMinutes ignora null y negativos', () {
      expect(sumMinutes(<int?>[100, null, -5, 50]), 150);
      expect(sumMinutes(<int?>[]), 0);
    });

    test('allKnown exige que no falte ningún valor', () {
      expect(allKnown(<int?>[1, 2, 3]), isTrue);
      expect(allKnown(<int?>[1, null, 3]), isFalse);
      expect(allKnown(<int?>[]), isTrue);
    });
  });

  group('aggregateByAppId', () {
    test('suma por AppID y nunca por nombre', () {
      final List<AggregatedGame> result = aggregateByAppId(<ProfileActivity>[
        _activity('a', const <Game>[
          Game(appId: 570, name: 'Dota 2', playtime2Weeks: 100, playtimeForever: 1000),
        ]),
        _activity('b', const <Game>[
          Game(appId: 570, name: 'Dota 2', playtime2Weeks: 50, playtimeForever: 2000),
        ]),
      ]);
      expect(result, hasLength(1));
      final AggregatedGame dota = result.single;
      expect(dota.appId, 570);
      expect(dota.recentMinutes, 150);
      expect(dota.foreverMinutes, 3000);
      expect(dota.memberCount, 2);
      expect(dota.contributions, hasLength(2));
      expect(dota.topSteamId64, 'a');
      expect(dota.topRecentMinutes, 100);
    });

    test('el acumulado agregado es null si a alguien le falta el dato', () {
      final List<AggregatedGame> result = aggregateByAppId(<ProfileActivity>[
        _activity('a', const <Game>[
          Game(appId: 570, playtime2Weeks: 100, playtimeForever: 1000),
        ]),
        _activity('b', const <Game>[
          Game(appId: 570, playtime2Weeks: 50),
        ]),
      ]);
      expect(result.single.foreverMinutes, isNull);
      expect(result.single.hasCompleteForever, isFalse);
    });

    test('ignora las actividades sin respuesta válida', () {
      final List<AggregatedGame> result = aggregateByAppId(<ProfileActivity>[
        _activity('a', const <Game>[
          Game(appId: 570, playtime2Weeks: 100),
        ]),
        _activity(
          'b',
          const <Game>[Game(appId: 730, playtime2Weeks: 999)],
          status: FetchStatus.networkError,
        ),
      ]);
      expect(result, hasLength(1));
      expect(result.single.appId, 570);
    });

    test('sin actividad reciente en ningún juego, topSteamId64 es null', () {
      final List<AggregatedGame> result = aggregateByAppId(<ProfileActivity>[
        _activity('a', const <Game>[Game(appId: 570, playtime2Weeks: 0)]),
      ]);
      expect(result.single.topSteamId64, isNull);
      expect(result.single.memberCount, 1);
    });

    test('se puede excluir actividades con include', () {
      final List<AggregatedGame> result = aggregateByAppId(
        <ProfileActivity>[
          _activity('a', const <Game>[Game(appId: 570, playtime2Weeks: 100)]),
          _activity('b', const <Game>[Game(appId: 730, playtime2Weeks: 100)]),
        ],
        include: (ProfileActivity a) => a.steamId64 == 'a',
      );
      expect(result.map((AggregatedGame g) => g.appId), <int>[570]);
    });
  });

  group('sortGames', () {
    const Game a = Game(appId: 570, name: 'Dota 2', playtime2Weeks: 100, playtimeForever: 1000);
    const Game b = Game(appId: 620, name: 'Portal 2', playtime2Weeks: 5, playtimeForever: 2000);
    const Game c = Game(appId: 730, name: 'CS2', playtime2Weeks: 50);

    test('por tiempo reciente descendente', () {
      final List<Game> sorted = sortGames(<Game>[b, c, a], GameSortOrder.recent);
      expect(sorted.map((Game g) => g.appId), <int>[570, 730, 620]);
    });

    test('por nombre ascendente', () {
      final List<Game> sorted = sortGames(<Game>[a, b, c], GameSortOrder.name);
      expect(sorted.map((Game g) => g.name), <String>['CS2', 'Dota 2', 'Portal 2']);
    });

    test('por tiempo acumulado dejando los desconocidos al final', () {
      final List<Game> sorted = sortGames(<Game>[a, c, b], GameSortOrder.forever);
      expect(sorted.last.appId, 730);
      expect(sorted.first.appId, 620);
    });
  });

  group('sortAggregatedGames', () {
    AggregatedGame game(int appId, String name, int recent, int? forever) =>
        AggregatedGame(
          appId: appId,
          name: name,
          recentMinutes: recent,
          foreverMinutes: forever,
          contributions: const <MemberContribution>[],
          memberCount: 1,
          topSteamId64: null,
          topDisplayName: name,
          topRecentMinutes: recent,
          coverUrl: null,
        );

    test('ordena por reciente, nombre y acumulado', () {
      final List<AggregatedGame> games = <AggregatedGame>[
        game(1, 'B', 10, 100),
        game(2, 'A', 50, null),
      ];
      expect(sortAggregatedGames(games, GameSortOrder.recent).first.name, 'A');
      expect(sortAggregatedGames(games, GameSortOrder.name).first.name, 'A');
      final List<AggregatedGame> byForever =
          sortAggregatedGames(games, GameSortOrder.forever);
      expect(byForever.first.name, 'B');
      expect(byForever.last.name, 'A');
    });
  });

  group('passesLowActivityFilter', () {
    test('sin filtro todo pasa', () {
      expect(passesLowActivityFilter(const Game(appId: 1), hide: false, threshold: 30), isTrue);
    });

    test('con filtro se exige el umbral', () {
      expect(
        passesLowActivityFilter(const Game(appId: 1, playtime2Weeks: 10), hide: true, threshold: 30),
        isFalse,
      );
      expect(
        passesLowActivityFilter(const Game(appId: 1, playtime2Weeks: 30), hide: true, threshold: 30),
        isTrue,
      );
    });
  });

  group('filterAndSortActivities', () {
    final List<ProfileActivity> activities = <ProfileActivity>[
      _activity('a', const <Game>[
        Game(appId: 570, name: 'Dota 2', playtime2Weeks: 100),
        Game(appId: 620, name: 'Portal 2', playtime2Weeks: 5),
      ], name: 'Ana'),
      _activity('b', const <Game>[
        Game(appId: 730, name: 'Counter-Strike 2', playtime2Weeks: 200),
      ], name: 'Bruno'),
    ];
    const Map<String, String> names = <String, String>{'a': 'Ana', 'b': 'Bruno'};

    test('buscar un integrante muestra todos sus juegos', () {
      final List<ProfileActivity> result = filterAndSortActivities(
        activities: activities,
        displayNames: names,
        query: 'ana',
      );
      expect(result.first.steamId64, 'a');
      expect(result.first.games, hasLength(2));
      expect(result.last.games, isEmpty);
    });

    test('buscar un juego filtra por nombre de juego', () {
      final List<ProfileActivity> result = filterAndSortActivities(
        activities: activities,
        displayNames: names,
        query: 'portal',
      );
      final ProfileActivity ana =
          result.firstWhere((ProfileActivity a) => a.steamId64 == 'a');
      expect(ana.games, hasLength(1));
      expect(ana.games.single.name, 'Portal 2');
    });

    test('el filtro de poca actividad elimina juegos pequeños', () {
      final List<ProfileActivity> result = filterAndSortActivities(
        activities: activities,
        displayNames: names,
        hideLowActivity: true,
        lowActivityMinutes: 30,
      );
      final ProfileActivity ana =
          result.firstWhere((ProfileActivity a) => a.steamId64 == 'a');
      expect(ana.games, hasLength(1));
      expect(ana.games.single.appId, 570);
    });

    test('soloSteamId64 restringe a un integrante', () {
      final List<ProfileActivity> result = filterAndSortActivities(
        activities: activities,
        displayNames: names,
        onlySteamId64: 'b',
      );
      expect(result, hasLength(1));
      expect(result.single.steamId64, 'b');
    });
  });

  group('totales y recuento', () {
    test('totalRecentMinutesOf es null si algún perfil falló', () {
      expect(totalRecentMinutesOf(const <ProfileActivity>[]), 0);
      expect(
        totalRecentMinutesOf(<ProfileActivity>[
          _activity('a', const <Game>[Game(appId: 570, playtime2Weeks: 100)]),
          _activity(
            'b',
            const <Game>[],
            status: FetchStatus.networkError,
          ),
        ]),
        isNull,
      );
      expect(
        totalRecentMinutesOf(<ProfileActivity>[
          _activity('a', const <Game>[Game(appId: 570, playtime2Weeks: 100)]),
          _activity('b', const <Game>[Game(appId: 730, playtime2Weeks: 100)]),
        ]),
        200,
      );
    });

    test('totalForeverMinutesOf es null si falta algún acumulado', () {
      expect(
        totalForeverMinutesOf(<ProfileActivity>[
          _activity('a', const <Game>[Game(appId: 570, playtime2Weeks: 1, playtimeForever: 10)]),
          _activity('b', const <Game>[Game(appId: 730, playtime2Weeks: 1)]),
        ]),
        isNull,
      );
    });

    test('distinctGameCount ignora actividades sin respuesta', () {
      expect(
        distinctGameCount(<ProfileActivity>[
          _activity('a', const <Game>[Game(appId: 570), Game(appId: 620)]),
          _activity('b', const <Game>[Game(appId: 570)], status: FetchStatus.networkError),
        ]),
        2,
      );
    });
  });
}
