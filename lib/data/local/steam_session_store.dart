/// Almacenamiento seguro de la sesión de Steam.
///
/// Reglas (las mismas que para la clave de Web API):
/// - Los tokens **nunca** se guardan en SQLite, en JSON, en preferencias
///   ordinarias ni en recursos de la aplicación.
/// - Solo se escriben en el almacenamiento seguro del dispositivo (Keystore en
///   Android, Keychain en iOS).
/// - No se registran ni se incluyen en mensajes de error.
///
/// Transparencia: el almacenamiento seguro protege el secreto **en reposo**. Un
/// dispositivo comprometido, con root o instrumentado, puede acceder a él.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants.dart';
import '../../core/models.dart';

/// Contrato de almacenamiento de la sesión.
///
/// Se define una interfaz para poder sustituir la implementación en pruebas sin
/// depender de los canales nativos de la plataforma.
abstract class SteamSessionStore {
  Future<SteamSession?> load();

  Future<void> save(SteamSession session);

  Future<void> clear();
}

/// Implementación real basada en `flutter_secure_storage`.
class SecureSteamSessionStore implements SteamSessionStore {
  SecureSteamSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<SteamSession?> load() async {
    final String? id = await _read(AppConstants.steamIdStorageKey);
    final String? access = await _read(AppConstants.steamAccessTokenStorageKey);
    final String? refresh = await _read(AppConstants.steamRefreshTokenStorageKey);
    if (id == null || access == null || refresh == null) {
      // Sesión incompleta (por ejemplo, una escritura interrumpida): se
      // descarta para no trabajar con datos a medias.
      if (id != null || access != null || refresh != null) {
        await clear();
      }
      return null;
    }
    final String? account = await _read(AppConstants.steamAccountNameStorageKey);
    return SteamSession(
      steamId64: id,
      accessToken: access,
      refreshToken: refresh,
      accountName: account,
      savedAtUnix: 0,
    );
  }

  @override
  Future<void> save(SteamSession session) async {
    await _storage.write(
      key: AppConstants.steamIdStorageKey,
      value: session.steamId64,
    );
    await _storage.write(
      key: AppConstants.steamAccessTokenStorageKey,
      value: session.accessToken,
    );
    await _storage.write(
      key: AppConstants.steamRefreshTokenStorageKey,
      value: session.refreshToken,
    );
    if (session.accountName != null && session.accountName!.isNotEmpty) {
      await _storage.write(
        key: AppConstants.steamAccountNameStorageKey,
        value: session.accountName,
      );
    } else {
      await _storage.delete(key: AppConstants.steamAccountNameStorageKey);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: AppConstants.steamIdStorageKey);
    await _storage.delete(key: AppConstants.steamAccessTokenStorageKey);
    await _storage.delete(key: AppConstants.steamRefreshTokenStorageKey);
    await _storage.delete(key: AppConstants.steamAccountNameStorageKey);
  }

  Future<String?> _read(String key) async {
    final String? value = await _storage.read(key: key);
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Implementación en memoria, pensada **exclusivamente para pruebas**.
class InMemorySteamSessionStore implements SteamSessionStore {
  InMemorySteamSessionStore([this._session]);

  SteamSession? _session;

  @override
  Future<SteamSession?> load() async => _session;

  @override
  Future<void> save(SteamSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
