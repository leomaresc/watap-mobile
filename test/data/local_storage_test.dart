/// Pruebas del almacenamiento local: persistencia, política de caché,
/// migraciones del esquema y aislamiento de la clave de API.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/local/app_database.dart';
import 'package:watap_mobile/data/local/database_migrations.dart';
import 'package:watap_mobile/data/repositories/activity_repository.dart';
import 'package:watap_mobile/data/repositories/preferences_repository.dart';
import 'package:watap_mobile/data/repositories/profiles_repository.dart';
import 'package:watap_mobile/state/app_controller.dart';

import '../helpers/test_support.dart';

const String _id = '76561198000000000';

Future<List<String>> _columnsOf(DatabaseExecutor db, String table) async {
  final List<Map<String, Object?>> info =
      await db.rawQuery('PRAGMA table_info($table)');
  return info.map((Map<String, Object?> r) => r['name'] as String).toList(growable: false);
}

Future<void> _expectKeyAbsentFromDatabase(AppDatabase db, String secret) async {
  for (final String table in <String>[
    Tables.profiles,
    Tables.profileActivities,
    Tables.games,
    Tables.preferences,
    Tables.cacheMetadata,
  ]) {
    final List<Map<String, Object?>> rows = await db.raw.query(table);
    for (final Map<String, Object?> row in rows) {
      for (final Object? value in row.values) {
        expect(
          '$value',
          isNot(contains(secret)),
          reason: 'La clave apareció en la tabla $table',
        );
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabaseFactory();

  group('persistencia de perfiles', () {
    late AppDatabase database;
    late ProfilesRepository repository;

    setUp(() async {
      database = await AppDatabase.open(inMemory: true);
      repository = ProfilesRepository(database);
    });
    tearDown(() => database.close());

    test('guarda, recarga y cuenta perfiles', () async {
      await repository.upsert(
        const Profile(steamId64: _id, personaName: 'Ana', createdAtUnix: 5),
      );
      final List<Profile> loaded = await repository.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.personaName, 'Ana');
      expect(await repository.exists(_id), isTrue);
      expect(await repository.count(), 1);
    });

    test('no se pueden duplicar perfiles con el mismo SteamID64', () async {
      await repository.upsert(
        const Profile(steamId64: _id, personaName: 'Ana', createdAtUnix: 5),
      );
      await repository.upsert(
        const Profile(steamId64: _id, alias: 'Ana local', createdAtUnix: 6),
      );
      expect(await repository.count(), 1);
      final Profile stored = (await repository.loadAll()).single;
      expect(stored.alias, 'Ana local');
    });

    test('solo un perfil puede estar marcado como propio', () async {
      await repository
          .upsert(const Profile(steamId64: _id, personaName: 'Ana', createdAtUnix: 1));
      await repository.upsert(
        const Profile(steamId64: '76561198000000009', personaName: 'Bruno', createdAtUnix: 2),
      );
      final List<Profile> loaded = await repository.loadAll();
      expect(loaded, hasLength(2));
      expect(loaded.first.steamId64, _id);
    });

    test('eliminar un perfil borra su actividad y sus juegos', () async {
      final ActivityRepository activities = ActivityRepository(database);
      await repository.upsert(
        const Profile(steamId64: _id, personaName: 'Ana', createdAtUnix: 1),
      );
      await activities.saveResult(
        const ProfileActivity(
          steamId64: _id,
          status: FetchStatus.ok,
          games: <Game>[Game(appId: 570, name: 'Dota 2', playtime2Weeks: 10)],
        ),
        previous: null,
      );
      expect(await activities.gamesCount(), 1);

      await repository.delete(_id);

      expect(await repository.count(), 0);
      expect(await activities.gamesCount(), 0);
      expect(await activities.loadOne(_id), isNull);
    });
  });

  group('política de caché', () {
    late AppDatabase database;
    late ActivityRepository repository;

    setUp(() async {
      database = await AppDatabase.open(inMemory: true);
      await ProfilesRepository(database)
          .upsert(const Profile(steamId64: _id, personaName: 'Ana', createdAtUnix: 1));
      repository = ActivityRepository(database);
    });
    tearDown(() => database.close());

    test('una respuesta válida reemplaza los juegos guardados', () async {
      await repository.saveResult(
        const ProfileActivity(
          steamId64: _id,
          status: FetchStatus.ok,
          games: <Game>[Game(appId: 570, name: 'Dota 2', playtime2Weeks: 100)],
        ),
        previous: null,
      );

      final ProfileActivity effective = await repository.saveResult(
        const ProfileActivity(steamId64: _id, status: FetchStatus.noRecentGames),
        previous: await repository.loadOne(_id),
      );

      expect(effective.games, isEmpty);
      expect(effective.fromCache, isFalse);
      expect((await repository.loadOne(_id))!.games, isEmpty);
    });

    test('un fallo conserva los datos anteriores y los marca como caché', () async {
      final ProfileActivity previous = await repository.saveResult(
        const ProfileActivity(
          steamId64: _id,
          status: FetchStatus.ok,
          games: <Game>[
            Game(appId: 570, name: 'Dota 2', playtime2Weeks: 100, playtimeForever: 1000),
          ],
        ),
        previous: null,
      );

      final ProfileActivity effective = await repository.saveResult(
        const ProfileActivity(
          steamId64: _id,
          status: FetchStatus.networkError,
          statusMessage: 'Sin conexión',
        ),
        previous: previous,
      );

      expect(effective.fromCache, isTrue);
      expect(effective.isStale, isTrue);
      expect(effective.games, hasLength(1));

      final ProfileActivity stored = (await repository.loadOne(_id))!;
      expect(stored.games, hasLength(1));
      expect(stored.status, FetchStatus.networkError);
      expect(stored.fromCache, isTrue);
    });
  });

  group('preferencias', () {
    late AppDatabase database;
    late PreferencesRepository repository;

    setUp(() async {
      database = await AppDatabase.open(inMemory: true);
      repository = PreferencesRepository(database);
    });
    tearDown(() => database.close());

    test('los valores por defecto se aplican cuando no hay nada guardado', () async {
      final Preferences prefs = await repository.load();
      expect(prefs.moderateActivityMinutes, 120);
      expect(prefs.highActivityMinutes, 480);
    });

    test('se guardan y se recargan los cambios', () async {
      final Preferences prefs = await repository.load();
      await repository.save(
        prefs.copyWith(
          hideLowActivity: true,
          showCovers: false,
          moderateActivityMinutes: 200,
          highActivityMinutes: 400,
          lastSection: 'overview',
        ),
      );
      final Preferences stored = await repository.load();
      expect(stored.hideLowActivity, isTrue);
      expect(stored.showCovers, isFalse);
      expect(stored.moderateActivityMinutes, 200);
      expect(stored.lastSection, 'overview');
    });

    test('reset devuelve a los valores por defecto', () async {
      final Preferences prefs = await repository.load();
      await repository.save(prefs.copyWith(hideLowActivity: true));
      final Preferences reset = await repository.reset();
      expect(reset.hideLowActivity, isFalse);
      expect((await repository.load()).hideLowActivity, isFalse);
    });
  });

  group('esquema y migraciones', () {
    test('una instalación nueva ya incluye las columnas migradas', () async {
      final AppDatabase database = await AppDatabase.open(inMemory: true);
      addTearDown(database.close);

      expect(await _columnsOf(database.raw, Tables.games), contains('icon_url'));
      expect(await _columnsOf(database.raw, Tables.profiles), contains('is_demo'));
      expect(await _columnsOf(database.raw, Tables.profiles), contains('is_family_member'));
      expect(DatabaseMigrations.steps.keys, containsAll(<int>[2, 3, 4]));
      expect(DatabaseMigrations.currentVersion, 4);
    });

    test('actualizar desde la versión 1 conserva los datos y añade columnas',
        () async {
      final Directory dir = await Directory.systemTemp.createTemp('watap_mig');
      addTearDown(() async {
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      final String path = p.join(dir.path, 'migracion.db');

      final Database v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: DatabaseMigrations.onCreate,
        ),
      );
      expect(await _columnsOf(v1, Tables.profiles), isNot(contains('is_demo')));
      expect(await _columnsOf(v1, Tables.games), isNot(contains('icon_url')));
      await v1.insert(Tables.profiles, <String, Object?>{
        'steam_id64': _id,
        'persona_name': 'Antiguo',
        'created_at': 1,
      });
      await v1.close();

      final Database upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseMigrations.currentVersion,
          singleInstance: false,
          onCreate: DatabaseMigrations.onCreate,
          onUpgrade: DatabaseMigrations.onUpgrade,
        ),
      );
      addTearDown(upgraded.close);

      expect(await _columnsOf(upgraded, Tables.profiles), contains('is_demo'));
      expect(await _columnsOf(upgraded, Tables.profiles), contains('is_family_member'));
      expect(await _columnsOf(upgraded, Tables.games), contains('icon_url'));
      final List<Map<String, Object?>> rows = await upgraded.query(Tables.profiles);
      expect(rows, hasLength(1));
      expect(rows.single['persona_name'], 'Antiguo');
      expect(rows.single['is_demo'], 0);
      expect(rows.single['is_family_member'], 0);
    });
  });

  group('aislamiento de la clave de API', () {
    test('la clave va al almacén seguro y no a la base de datos', () async {
      const String secret = 'clave-secreta-para-la-prueba-0001';
      final TestEnvironment environment =
          await buildTestEnvironment(httpClient: FakeHttpClient((_) => jsonResponse('{}')));
      addTearDown(environment.dispose);

      final OperationResult result = await environment.controller.saveApiKey(secret);

      expect(result.success, isTrue);
      expect(environment.controller.hasApiKey, isTrue);
      expect(await environment.keyStore.loadApiKey(), secret);
      await _expectKeyAbsentFromDatabase(environment.database, secret);
    });
  });
}
