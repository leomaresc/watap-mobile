/// Prueba mínima para comprobar que la infraestructura de pruebas funciona:
/// SQLite en memoria mediante FFI, sin emulador ni dispositivo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/local/app_database.dart';
import 'package:watap_mobile/data/repositories/profiles_repository.dart';

import 'helpers/test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabaseFactory();

  test('la base de datos en memoria funciona y persiste perfiles', () async {
    final AppDatabase database = await AppDatabase.open(inMemory: true);
    addTearDown(database.close);
    final ProfilesRepository repository = ProfilesRepository(database);
    await repository.upsert(
      const Profile(
        steamId64: '76561198000000000',
        personaName: 'Prueba',
        createdAtUnix: 1,
      ),
    );
    final List<Profile> loaded = await repository.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.personaName, 'Prueba');
  });
}
