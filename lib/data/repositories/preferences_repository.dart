/// Persistencia de preferencias en la tabla `preferences` (clave/valor).
library;

import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../local/app_database.dart';
import '../local/database_migrations.dart';

/// Repositorio de preferencias.
class PreferencesRepository {
  PreferencesRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.raw;

  /// Carga las preferencias guardadas, aplicando valores por defecto a las
  /// claves ausentes y saneando los umbrales.
  Future<Preferences> load() async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.preferences,
      columns: <String>['key', 'value'],
    );
    final Map<String, String> map = <String, String>{};
    for (final Map<String, Object?> row in rows) {
      final String? key = row['key'] as String?;
      if (key == null) continue;
      map[key] = (row['value'] as String?) ?? '';
    }
    return Preferences.fromKeyValueMap(map);
  }

  /// Guarda todas las preferencias en una sola transacción.
  Future<void> save(Preferences preferences) async {
    final Preferences safe = preferences.sanitized();
    final Map<String, String> map = safe.toKeyValueMap();
    await _db.transaction((Transaction txn) async {
      for (final MapEntry<String, String> entry in map.entries) {
        await txn.insert(
          Tables.preferences,
          <String, Object?>{'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Restablece las preferencias a sus valores por defecto.
  Future<Preferences> reset() async {
    await _db.delete(Tables.preferences);
    const Preferences defaults = Preferences.defaults();
    await save(defaults);
    return defaults;
  }
}
