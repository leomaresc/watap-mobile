/// Apertura y ciclo de vida de la base de datos SQLite local.
///
/// La base de datos contiene perfiles, actividades, juegos, preferencias y
/// metadatos de caché. **Nunca contiene credenciales**: el token de sesión de
/// Steam se guarda exclusivamente en el almacenamiento seguro del dispositivo
/// (ver `SteamTokenStore`).
library;

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import 'database_migrations.dart';

/// Envoltorio de la base de datos de la aplicación.
class AppDatabase {
  AppDatabase._(this._db, this.filePath);

  final Database _db;

  /// Ruta del archivo de base de datos, o `:memory:` en pruebas.
  final String filePath;

  /// Acceso directo para los repositorios.
  Database get raw => _db;

  bool _closed = false;

  bool get isOpen => !_closed;

  /// Abre (o crea) la base de datos.
  ///
  /// [factory] permite inyectar `databaseFactoryFfi` en las pruebas.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? fileName,
    bool inMemory = false,
  }) async {
    final DatabaseFactory dbFactory = factory ?? databaseFactory;
    final String path = inMemory
        ? inMemoryDatabasePath
        : p.join(await dbFactory.getDatabasesPath(),
            fileName ?? AppConstants.databaseFileName);

    final Database db = await dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseMigrations.currentVersion,
        onConfigure: _onConfigure,
        onCreate: DatabaseMigrations.onCreate,
        onUpgrade: DatabaseMigrations.onUpgrade,
      ),
    );
    return AppDatabase._(db, path);
  }

  /// Activa las claves foráneas (desactivadas por defecto en SQLite).
  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Borra todas las filas de datos de usuario conservando el esquema.
  ///
  /// Se usa en "Borrar caché de actividad". La lista de perfiles se puede
  /// conservar o eliminar según [includeProfiles].
  Future<void> clearUserData({bool includeProfiles = false}) async {
    await _db.transaction((Transaction txn) async {
      await txn.delete(Tables.games);
      await txn.delete(Tables.profileActivities);
      await txn.delete(Tables.cacheMetadata);
      if (includeProfiles) {
        await txn.delete(Tables.profiles);
      }
    });
  }

  /// Elimina por completo el archivo de base de datos (reinicio total).
  Future<void> deleteEverything() async {
    await _db.close();
    _closed = true;
    if (filePath != inMemoryDatabasePath) {
      await databaseFactory.deleteDatabase(filePath);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }
}
