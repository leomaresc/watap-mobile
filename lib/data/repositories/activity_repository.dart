/// Acceso a `profile_activities` y `games`, con la política de caché.
///
/// Regla central: **los datos válidos no se reemplazan por resultados vacíos
/// derivados de un error**. Si una consulta falla y ya había información
/// guardada, se conserva y se marca como procedente de la caché.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../local/app_database.dart';
import '../local/database_migrations.dart';

/// Repositorio de actividad de perfiles.
class ActivityRepository {
  ActivityRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.raw;

  /// Carga todas las actividades guardadas, indexadas por SteamID64.
  Future<Map<String, ProfileActivity>> loadAll() async {
    final List<Map<String, Object?>> activityRows = await _db.rawQuery('''
      SELECT a.*, p.persona_name AS persona_name, p.avatar_url AS avatar_url
      FROM ${Tables.profileActivities} a
      LEFT JOIN ${Tables.profiles} p ON p.steam_id64 = a.steam_id64
    ''');

    final Map<String, List<Game>> gamesByProfile = await _loadGamesByProfile();

    final Map<String, ProfileActivity> result = <String, ProfileActivity>{};
    for (final Map<String, Object?> row in activityRows) {
      final String? id = row['steam_id64'] as String?;
      if (id == null || id.isEmpty) continue;
      result[id] = ProfileActivity.fromMap(
        row,
        games: gamesByProfile[id] ?? const <Game>[],
        personaName: row['persona_name'] as String?,
        avatarUrl: row['avatar_url'] as String?,
      );
    }
    return result;
  }

  Future<ProfileActivity?> loadOne(String steamId64) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery('''
      SELECT a.*, p.persona_name AS persona_name, p.avatar_url AS avatar_url
      FROM ${Tables.profileActivities} a
      LEFT JOIN ${Tables.profiles} p ON p.steam_id64 = a.steam_id64
      WHERE a.steam_id64 = ?
      LIMIT 1
    ''', <Object?>[steamId64]);
    if (rows.isEmpty) return null;
    final List<Game> games = await _loadGames(steamId64);
    return ProfileActivity.fromMap(
      rows.first,
      games: games,
      personaName: rows.first['persona_name'] as String?,
      avatarUrl: rows.first['avatar_url'] as String?,
    );
  }

  Future<Map<String, List<Game>>> _loadGamesByProfile() async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.games,
      orderBy: 'playtime_2weeks DESC, app_id ASC',
    );
    final Map<String, List<Game>> grouped = <String, List<Game>>{};
    for (final Map<String, Object?> row in rows) {
      final String id = (row['steam_id64'] as String?) ?? '';
      if (id.isEmpty) continue;
      grouped.putIfAbsent(id, () => <Game>[]).add(Game.fromMap(row));
    }
    return grouped;
  }

  Future<List<Game>> _loadGames(String steamId64) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.games,
      where: 'steam_id64 = ?',
      whereArgs: <Object?>[steamId64],
      orderBy: 'playtime_2weeks DESC, app_id ASC',
    );
    return rows.map(Game.fromMap).toList(growable: false);
  }

  /// Guarda el resultado de una consulta aplicando la política de caché.
  ///
  /// - Respuesta válida (`ok`, `noRecentGames`): se sustituyen los juegos y se
  ///   actualiza `last_success_at`.
  /// - Fallo (`networkError`, `privateOrUnavailable`, …): se conservan los
  ///   juegos anteriores si existen, se marca `from_cache`/`is_stale` y solo se
  ///   actualiza el estado y la fecha del intento.
  ///
  /// Devuelve la actividad efectiva, que es la que debe mostrarse.
  Future<ProfileActivity> saveResult(
    ProfileActivity result, {
    required ProfileActivity? previous,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (result.status.isAnswered) {
      final ProfileActivity effective = result.copyWith(
        fetchedAtUnix: result.fetchedAtUnix ?? now,
        lastSuccessAtUnix: now,
        fromCache: false,
        isStale: false,
      );
      await _persist(effective, replaceGames: true);
      return effective;
    }

    // Fallo: se conserva lo que ya había.
    final List<Game> cachedGames = previous?.games ?? const <Game>[];
    final int? lastSuccess = previous?.lastSuccessAtUnix;
    final bool hasCache = cachedGames.isNotEmpty;

    final ProfileActivity effective = result.copyWith(
      games: cachedGames,
      fetchedAtUnix: now,
      lastSuccessAtUnix: lastSuccess,
      fromCache: hasCache,
      isStale: true,
    );
    await _persist(effective, replaceGames: false);
    return effective;
  }

  /// Guarda un estado sin modificar los juegos ya almacenados.
  Future<void> saveStatusOnly(ProfileActivity activity) =>
      _persist(activity, replaceGames: false);

  Future<void> _persist(ProfileActivity activity, {required bool replaceGames}) async {
    await _db.transaction((Transaction txn) async {
      await txn.insert(
        Tables.profileActivities,
        activity.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (replaceGames) {
        await txn.delete(
          Tables.games,
          where: 'steam_id64 = ?',
          whereArgs: <Object?>[activity.steamId64],
        );
        final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        for (final Game game in activity.games) {
          await txn.insert(
            Tables.games,
            <String, Object?>{
              'steam_id64': activity.steamId64,
              'app_id': game.appId,
              'name': game.name,
              'playtime_2weeks': game.playtime2Weeks,
              'playtime_forever': game.playtimeForever,
              'has_playtime_forever': game.hasPlaytimeForever ? 1 : 0,
              'cover_url': game.coverUrl,
              'icon_url': game.iconUrl,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  /// Elimina la actividad y los juegos de un perfil.
  Future<void> delete(String steamId64) async {
    await _db.transaction((Transaction txn) async {
      await txn.delete(
        Tables.games,
        where: 'steam_id64 = ?',
        whereArgs: <Object?>[steamId64],
      );
      await txn.delete(
        Tables.profileActivities,
        where: 'steam_id64 = ?',
        whereArgs: <Object?>[steamId64],
      );
    });
  }

  /// Número total de filas de juegos almacenadas.
  Future<int> gamesCount() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM ${Tables.games}'),
        ) ??
        0;
  }

  /// Escribe un metadato de caché (por ejemplo, la última actualización global).
  Future<void> writeMetadata(String key, String? value) async {
    await _db.insert(
      Tables.cacheMetadata,
      <String, Object?>{
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int?> readMetadataUpdatedAt(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.cacheMetadata,
      columns: <String>['updated_at'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Object? value = rows.first['updated_at'];
    return value is int ? value : null;
  }
}
