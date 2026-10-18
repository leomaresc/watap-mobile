/// Acceso a la tabla `profiles`.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../local/app_database.dart';
import '../local/database_migrations.dart';

/// Repositorio de perfiles supervisados.
class ProfilesRepository {
  ProfilesRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.raw;

  /// Carga todos los perfiles ordenados por creación.
  Future<List<Profile>> loadAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.profiles,
      orderBy: 'created_at ASC, persona_name COLLATE NOCASE ASC',
    );
    return rows.map(Profile.fromMap).toList(growable: false);
  }

  Future<Profile?> findById(String steamId64) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.profiles,
      where: 'steam_id64 = ?',
      whereArgs: <Object?>[steamId64],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Profile.fromMap(rows.first);
  }

  /// `true` si el SteamID64 ya está registrado (sin importar el alias).
  Future<bool> exists(String steamId64) async {
    final int count = Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM ${Tables.profiles} WHERE steam_id64 = ?',
            <Object?>[steamId64],
          ),
        ) ??
        0;
    return count > 0;
  }

  /// Inserta o actualiza un perfil.
  ///
  /// La clave primaria es el SteamID64, por lo que dos perfiles con el mismo
  /// identificador y distinto alias son la misma fila: no se pueden duplicar.
  Future<void> upsert(Profile profile) async {
    await _db.insert(
      Tables.profiles,
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Elimina el perfil y, en cascada, su actividad y sus juegos.
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
      await txn.delete(
        Tables.profiles,
        where: 'steam_id64 = ?',
        whereArgs: <Object?>[steamId64],
      );
    });
  }

  /// Marca un único perfil como "perfil propio" (o ninguno con `null`).
  Future<void> setOwnProfile(String? steamId64) async {
    await _db.transaction((Transaction txn) async {
      await txn.update(Tables.profiles, <String, Object?>{'is_own_profile': 0});
      if (steamId64 != null) {
        await txn.update(
          Tables.profiles,
          <String, Object?>{'is_own_profile': 1},
          where: 'steam_id64 = ?',
          whereArgs: <Object?>[steamId64],
        );
      }
    });
  }

  /// Actualiza el nombre público y el avatar con los datos que devuelve Steam.
  ///
  /// No crea perfiles: solo refresca los que ya existen.
  Future<void> applySummary(SteamPlayerSummary summary) async {
    final Map<String, Object?> values = <String, Object?>{
      if (summary.personaName != null) 'persona_name': summary.personaName,
      if (summary.avatarUrl != null) 'avatar_url': summary.avatarUrl,
    };
    if (values.isEmpty) return;
    await _db.update(
      Tables.profiles,
      values,
      where: 'steam_id64 = ?',
      whereArgs: <Object?>[summary.steamId64],
    );
  }

  Future<int> count() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM ${Tables.profiles}'),
        ) ??
        0;
  }
}
