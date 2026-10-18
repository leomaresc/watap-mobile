/// Gestión de la clave de Steam Web API en el almacenamiento seguro.
///
/// Reglas de la aplicación:
/// - La clave **nunca** se guarda en SQLite, en JSON, en preferencias
///   ordinarias, en recursos del APK/IPA ni en registros.
/// - Solo se escribe la clave completa cuando el usuario la introduce
///   voluntariamente en el formulario.
/// - No se registra ni se incluye en mensajes de error.
///
/// Transparencia: el almacenamiento seguro protege el secreto **en reposo**
/// (Keystore en Android, Keychain en iOS). Una aplicación cliente no puede
/// garantizar protección absoluta frente a un dispositivo comprometido, con
/// acceso root o con ejecución instrumentada.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants.dart';

/// Contrato de almacenamiento de la clave.
///
/// Se define una interfaz para poder sustituir la implementación en pruebas
/// sin depender de los canales nativos de la plataforma.
abstract class ApiKeyStore {
  Future<void> saveApiKey(String apiKey);

  Future<String?> loadApiKey();

  Future<void> deleteApiKey();

  Future<bool> hasApiKey();
}

/// Implementación real basada en `flutter_secure_storage`.
class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Clave interna del almacén seguro. No es un secreto.
  static const String storageKey = AppConstants.apiKeyStorageKey;

  @override
  Future<void> saveApiKey(String apiKey) async {
    final String value = apiKey.trim();
    if (value.isEmpty) {
      await deleteApiKey();
      return;
    }
    await _storage.write(key: storageKey, value: value);
  }

  @override
  Future<String?> loadApiKey() async {
    final String? value = await _storage.read(key: storageKey);
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> deleteApiKey() async {
    await _storage.delete(key: storageKey);
  }

  @override
  Future<bool> hasApiKey() async {
    final String? value = await loadApiKey();
    return value != null && value.isNotEmpty;
  }
}

/// Implementación en memoria, pensada **exclusivamente para pruebas**.
///
/// No se usa en la aplicación real; permite verificar que la clave no acaba en
/// SQLite y que el resto de capas funciona con una clave configurada.
class InMemoryApiKeyStore implements ApiKeyStore {
  InMemoryApiKeyStore([this._value]);

  String? _value;

  @override
  Future<void> saveApiKey(String apiKey) async {
    final String value = apiKey.trim();
    _value = value.isEmpty ? null : value;
  }

  @override
  Future<String?> loadApiKey() async => _value;

  @override
  Future<void> deleteApiKey() async {
    _value = null;
  }

  @override
  Future<bool> hasApiKey() async => _value != null && _value!.isNotEmpty;
}
