/// Definición del esquema y de las migraciones de la base de datos local.
///
/// Estrategia:
/// - `onCreate` crea el esquema **inicial** (versión 1) y después aplica todas
///   las migraciones hasta la versión actual. Así el camino de migración se
///   ejercita también en instalaciones nuevas y no puede quedarse obsoleto.
/// - `onUpgrade` aplica las migraciones pendientes sin descartar datos.
/// - `sqflite` ejecuta `onCreate`/`onUpgrade` dentro de una transacción, por lo
///   que un fallo no deja el esquema a medias.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';

/// Nombres de tabla usados por la aplicación.
class Tables {
  const Tables._();

  static const String profiles = 'profiles';
  static const String profileActivities = 'profile_activities';
  static const String games = 'games';
  static const String preferences = 'preferences';
  static const String cacheMetadata = 'cache_metadata';
}

/// Paso de migración: recibe el ejecutor de base de datos.
typedef MigrationStep = Future<void> Function(DatabaseExecutor db);

/// Migraciones del esquema.
class DatabaseMigrations {
  const DatabaseMigrations._();

  /// Versión del esquema creada por `_createBaseline`.
  static const int baselineVersion = AppConstants.databaseMigrationBaselineVersion;

  /// Versión actual del esquema.
  static const int currentVersion = AppConstants.databaseVersion;

  /// Migraciones indexadas por la versión de destino.
  static Map<int, MigrationStep> get steps => <int, MigrationStep>{
        2: _addGameIconUrl,
        3: _addProfileIsDemo,
      };

  /// Crea el esquema inicial y aplica las migraciones restantes.
  static Future<void> onCreate(Database db, int version) async {
    await _createBaseline(db);
    await _applyUpgrades(db, baselineVersion + 1, version);
  }

  /// Aplica las migraciones necesarias al actualizar una base existente.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _applyUpgrades(db, oldVersion + 1, newVersion);
  }

  static Future<void> _applyUpgrades(Database db, int fromInclusive, int toInclusive) async {
    for (int v = fromInclusive; v <= toInclusive; v++) {
      final MigrationStep? step = steps[v];
      if (step != null) await step(db);
    }
  }

  /// Esquema de la versión 1.
  static Future<void> _createBaseline(Database db) async {
    await db.execute('''
      CREATE TABLE ${Tables.profiles} (
        steam_id64       TEXT    PRIMARY KEY,
        persona_name     TEXT,
        avatar_url       TEXT,
        alias            TEXT,
        is_own_profile   INTEGER NOT NULL DEFAULT 0,
        created_at       INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${Tables.profileActivities} (
        steam_id64            TEXT    PRIMARY KEY,
        status                TEXT    NOT NULL DEFAULT 'notFetched',
        status_message        TEXT,
        fetched_at            INTEGER,
        last_success_at       INTEGER,
        from_cache            INTEGER NOT NULL DEFAULT 0,
        is_stale              INTEGER NOT NULL DEFAULT 0,
        total_recent_minutes  INTEGER,
        total_forever_minutes INTEGER,
        games_count           INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (steam_id64) REFERENCES ${Tables.profiles} (steam_id64)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${Tables.games} (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        steam_id64          TEXT    NOT NULL,
        app_id              INTEGER NOT NULL,
        name                TEXT,
        playtime_2weeks     INTEGER NOT NULL DEFAULT 0,
        playtime_forever    INTEGER,
        has_playtime_forever INTEGER NOT NULL DEFAULT 0,
        cover_url           TEXT,
        updated_at          INTEGER NOT NULL DEFAULT 0,
        UNIQUE (steam_id64, app_id),
        FOREIGN KEY (steam_id64) REFERENCES ${Tables.profiles} (steam_id64)
          ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_games_app_id ON ${Tables.games} (app_id)',
    );

    await db.execute('''
      CREATE TABLE ${Tables.preferences} (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${Tables.cacheMetadata} (
        key        TEXT PRIMARY KEY,
        value      TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Migración a la versión 2: se añade el icono del juego.
  ///
  /// La aplicación empezó guardando solo la portada; los iconos del CDN de
  /// Steam (`img_icon_url`) se incorporaron después como recurso alternativo
  /// cuando una portada no está disponible.
  static Future<void> _addGameIconUrl(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE ${Tables.games} ADD COLUMN icon_url TEXT');
  }

  /// Migración a la versión 3: se marca si un perfil pertenece al modo
  /// demostración.
  ///
  /// La bandera debe sobrevivir al cierre de la aplicación para que los datos
  /// ficticios se sigan etiquetando como tales en cada apertura.
  static Future<void> _addProfileIsDemo(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE ${Tables.profiles} ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0',
    );
  }
}
