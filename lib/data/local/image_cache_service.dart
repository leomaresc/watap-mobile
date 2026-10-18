/// Gestión de la caché de imágenes (portadas e iconos).
///
/// Se apoya en `cached_network_image` / `flutter_cache_manager`, que ya:
/// - reutiliza los archivos entre sesiones,
/// - evita descargar dos veces la misma URL de forma simultánea,
/// - tolera fallos sin bloquear la interfaz.
///
/// Este servicio añade lo que la aplicación necesita en Ajustes: conocer el
/// tamaño ocupado y poder vaciar la caché.
library;

import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Servicio de caché de imágenes.
class ImageCacheService {
  ImageCacheService({BaseCacheManager? cacheManager})
      : _injectedManager = cacheManager;

  /// Gestor inyectado (pruebas). Si es `null` se usa el predeterminado.
  final BaseCacheManager? _injectedManager;

  BaseCacheManager? _manager;

  /// El gestor de caché se crea **bajo demanda**.
  ///
  /// Construir el servicio —o solo calcular el tamaño de la caché— no debe
  /// tocar el almacenamiento de la plataforma: hacerlo en el constructor
  /// provocaría errores en entornos sin `path_provider` (por ejemplo, las
  /// pruebas) aunque no se llegue a usar la caché.
  BaseCacheManager? get _cacheManager =>
      _manager ??= _injectedManager ?? _createDefaultManager();

  static BaseCacheManager? _createDefaultManager() {
    try {
      return DefaultCacheManager();
    } catch (_) {
      return null;
    }
  }

  /// Carpeta que usa `flutter_cache_manager` por defecto.
  static const String defaultCacheFolderName = 'libCachedImageData';

  Future<Directory?> _cacheDirectory() async {
    try {
      final Directory temp = await getTemporaryDirectory();
      final Directory dir = Directory(p.join(temp.path, defaultCacheFolderName));
      return dir;
    } catch (_) {
      // En plataformas sin `path_provider` (por ejemplo, en pruebas) se
      // devuelve null y las operaciones de caché quedan como "no disponibles".
      return null;
    }
  }

  /// Tamaño aproximado de la caché en bytes.
  ///
  /// Devuelve `0` si no se puede determinar (nunca lanza).
  Future<int> cacheSizeBytes() async {
    final Directory? dir = await _cacheDirectory();
    if (dir == null || !await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final FileSystemEntity entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // Archivo eliminado mientras se recorría la carpeta.
          }
        }
      }
    } catch (_) {
      return total;
    }
    return total;
  }

  /// Vacía la caché de imágenes.
  ///
  /// Devuelve `true` si la operación se completó sin errores graves.
  Future<bool> clearCache() async {
    bool ok = true;
    final BaseCacheManager? manager = _cacheManager;
    if (manager != null) {
      try {
        await manager.emptyCache();
      } catch (_) {
        ok = false;
      }
    }
    try {
      final Directory? dir = await _cacheDirectory();
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      ok = false;
    }
    return ok;
  }

  /// Formatea un tamaño en bytes para mostrarlo en Ajustes.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
