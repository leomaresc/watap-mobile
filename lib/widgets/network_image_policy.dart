/// Interruptor global de carga de imágenes remotas.
///
/// En la aplicación siempre está activo. Las pruebas de widgets lo desactivan
/// para no depender de la red ni de los canales nativos de `path_provider`
/// (caché en disco). No es una preferencia de usuario.
library;

bool watapRemoteImagesEnabled = true;
