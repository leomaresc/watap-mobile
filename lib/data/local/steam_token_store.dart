/// Almacenamiento seguro del `webapi_token` de la sesión de Steam.
///
/// Ese token es lo que permite leer el grupo familiar (`IFamilyGroupsService`).
/// La clave de Web API no sirve para eso.
///
/// Reglas (las mismas que para la clave de API):
/// - El token **nunca** se guarda en SQLite, en JSON, en preferencias
///   ordinarias ni en recursos de la aplicación.
/// - Solo se escribe en el almacenamiento seguro del dispositivo (Keystore en
///   Android, Keychain en iOS).
/// - No se registra ni se incluye en mensajes de error.
///
/// Es un token **temporal**: Steam lo caduca de vez en cuando y entonces hay
/// que volver a conectar la cuenta (ver `SteamConnectScreen`).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants.dart';

/// Contrato de almacenamiento del token de sesión de Steam.
///
/// Interfaz para poder sustituir la implementación en pruebas sin depender de
/// los canales nativos de la plataforma.
abstract class SteamTokenStore {
  Future<String?> load();

  Future<void> save(String token);

  Future<void> clear();
}

/// Implementación real basada en `flutter_secure_storage`.
class SecureSteamTokenStore implements SteamTokenStore {
  SecureSteamTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Nombre de la entrada en el almacén seguro. No es un secreto.
  static const String storageKey = AppConstants.steamTokenStorageKey;

  @override
  Future<String?> load() async {
    final String? value = await _storage.read(key: storageKey);
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> save(String token) async {
    final String value = token.trim();
    if (value.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: storageKey, value: value);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: storageKey);
  }
}

/// Implementación en memoria, pensada **exclusivamente para pruebas**.
class InMemorySteamTokenStore implements SteamTokenStore {
  InMemorySteamTokenStore([this._value]);

  String? _value;

  @override
  Future<String?> load() async => _value;

  @override
  Future<void> save(String token) async {
    final String value = token.trim();
    _value = value.isEmpty ? null : value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}
