# WATAP Mobile

**WATAP** son las siglas de *What Are They Actually Playing?* («¿A qué están
jugando realmente?»).

WATAP Mobile es una aplicación **Flutter** (Android primero, compatible con iOS)
que permite **consultar y comparar la actividad reciente de Steam** de un
conjunto de perfiles que tú añades manualmente: cuántos minutos ha registrado
Steam para cada juego en las últimas dos semanas y su tiempo acumulado.

La aplicación está pensada para ser **honesta con los datos**: nunca presenta un
cero engañoso cuando Steam no ha comunicado un valor, distingue "no hay juegos
recientes" de "el perfil es privado o no está disponible", y marca de forma
inequívoca los datos ficticios del modo demostración.

> **WATAP Mobile es un proyecto independiente.** No está afiliado, asociado,
> autorizado ni respaldado por Valve Corporation. Steam es una marca registrada
> de Valve Corporation. Consulta el apartado
> [Licencia y descargos](#21-licencia-y-descargos).

---

## Índice

1. [Qué es WATAP Mobile](#1-qué-es-watap-mobile)
2. [Qué hace](#2-qué-hace)
3. [Qué NO hace (límites por diseño)](#3-qué-no-hace-límites-por-diseño)
4. [Aviso importante sobre la interpretación de los datos](#4-aviso-importante-sobre-la-interpretación-de-los-datos)
5. [Requisitos](#5-requisitos)
6. [Compilación e instalación](#6-compilación-e-instalación)
7. [Obtener una clave de Steam Web API](#7-obtener-una-clave-de-steam-web-api)
8. [Configurar la clave en la aplicación](#8-configurar-la-clave-en-la-aplicación)
9. [Conectar con Steam (grupo familiar)](#9-conectar-con-steam-grupo-familiar)
10. [Uso de la aplicación](#10-uso-de-la-aplicación)
11. [Privacidad y datos almacenados](#11-privacidad-y-datos-almacenados)
12. [Permisos](#12-permisos)
13. [Endpoints de Steam utilizados](#13-endpoints-de-steam-utilizados)
14. [Arquitectura del código](#14-arquitectura-del-código)
15. [Modelo de datos y política de caché](#15-modelo-de-datos-y-política-de-caché)
16. [Pruebas automatizadas](#16-pruebas-automatizadas)
17. [Análisis estático](#17-análisis-estático)
18. [Limitaciones conocidas](#18-limitaciones-conocidas)
19. [Hoja de ruta](#19-hoja-de-ruta)
20. [Estructura del repositorio](#20-estructura-del-repositorio)
21. [Licencia y descargos](#21-licencia-y-descargos)

---

## 1. Qué es WATAP Mobile

Una aplicación de escritorio-a-bolsillo para responder a una pregunta concreta y
acotada:

> «¿Cuánto han jugado últimamente las personas de mi grupo y a qué?»

WATAP no intenta ser una red social, ni un rastreador de estado en tiempo real,
ni un panel de grupos familiares de Steam. Es una **herramienta de consulta**
que resume, en una sola pantalla, información que Steam ya publica a través de
su **Web API pública y documentada**.

Idioma de la interfaz: **español**.

---

## 2. Qué hace

- **Importa tus integrantes automáticamente desde tu grupo familiar de Steam.**
  Conectas tu cuenta una vez (con la página oficial de Steam en un WebView) y
  WATAP lee tu familia con `IFamilyGroupsService`, añadiendo cada integrante
  con su nombre público y avatar. **No tienes que copiar enlaces a mano.**
- **Importar integrantes a mano (respaldo)**: pega una lista de SteamID64, URLs
  de perfil o nombres personalizados. Cada entrada se procesa individualmente:
  una inválida no aborta el resto.
- **Añadir un perfil individual** por SteamID64, URL o nombre personalizado.
- **Consultar la actividad reciente** con `GetRecentlyPlayedGames`: minutos de
  las últimas dos semanas y tiempo acumulado, por juego y por integrante.
- **Vista "Recientes"**: juegos agrupados por integrante, con búsqueda por juego
  o persona, filtro por integrante, filtro de "poca actividad" y ordenación por
  tiempo reciente, nombre o tiempo total.
- **Vista "General"**: actividad **agregada por AppID** de todos los
  integrantes, con desglose por persona y sumas totales. La agregación se hace
  siempre por **AppID**, nunca por nombre de juego.
- **Vista "Integrantes"**: lista de perfiles con sincronización del grupo
  familiar, edición de alias, apertura en Steam y eliminación.
- **Vista "Ajustes"**: gestión de la clave de API, conexión con Steam, umbrales
  de actividad, preferencias de visualización, caché y pantallas de privacidad
  y "Acerca de".
- **Caché local**: guarda la última consulta correcta y **la conserva** cuando un
  intento posterior falla, marcándola como procedente de la caché.

---

## 3. Qué NO hace (límites por diseño)

Estas ausencias son **decisiones deliberadas**, no funciones pendientes:

- **No** consulta el estado "en línea ahora" ni afirma que alguien esté jugando
  en este momento.
- **No** hace *scraping* de perfiles de `steamcommunity.com`.
- **No** lee archivos locales de Steam (por ejemplo, de una instalación de
  Windows), ni registros, ni archivos de configuración del cliente.
- **No** ve ni guarda tu contraseña de Steam. El inicio de sesión ocurre en la
  **página oficial de Valve** dentro de un WebView; WATAP solo recibe un token
  temporal después.
- **No** almacena tu contraseña ni cookies de sesión. Solo guarda un token
  temporal (`webapi_token`) en el almacenamiento seguro, para poder leer el
  grupo familiar sin volver a pedirte la contraseña.
- **No** ejecuta procesos en segundo plano ni temporizadores periódicos: todo
  ocurre como operaciones asíncronas mientras la aplicación está abierta.
- **No** envía telemetría, analíticas ni datos de uso a ningún servidor propio.
- **No** incluye anuncios (ver [Hoja de ruta](#19-hoja-de-ruta)).
- **No** sincroniza datos entre dispositivos ni con la nube.
- **No** solicita permisos que no sean estrictamente necesarios (ver
  [Permisos](#12-permisos)).

---

## 4. Aviso importante sobre la interpretación de los datos

Lee esto antes de sacar conclusiones:

- **Los datos pertenecen a Steam y los comunica Steam.** WATAP solo los presenta.
- **No son tiempo real.** Son los minutos que Steam comunica en `GetRecentlyPlayedGames`
  para las **últimas dos semanas** (y el acumulado histórico del perfil),
  calculados por Steam, no por WATAP.
- **Un "0" solo aparece cuando Steam confirma un cero.** Si Steam no comunica un
  valor, WATAP muestra **`—`**, nunca `0`. Un acumulado agregado se muestra como
  guion si a algún integrante le falta ese dato, para no presentar un total
  parcial como si fuera completo.
- **"Sin juegos recientes" ≠ "no juega nunca".** Una respuesta válida sin juegos
  solo significa que, según Steam, no hay actividad registrada en las últimas
  dos semanas. Se distingue explícitamente del caso "privado o no disponible".
- **Las sumas del grupo son sumas de tiempo registrado por Steam.** No
  representan juego simultáneo, ni sesiones compartidas, ni el estado actual de
  nadie.
- **Un perfil privado no es un error tuyo.** Si los "Detalles del juego" del
  perfil son privados, Steam no entrega los datos y WATAP lo explica tal cual.

---

## 5. Requisitos

Para **usar** la aplicación:

- Android 7.0 (API 24) o superior.
- Conexión a Internet (solo para consultar Steam y descargar portadas y
  avatares). El modo demostración funciona sin conexión.
- Una **clave de Steam Web API** para consultar perfiles reales (no es necesaria
  para el modo demostración).

Para **compilar** el proyecto:

- [Flutter](https://docs.flutter.dev/get-started/install) en el canal *stable*.
- **Dart** (se instala con Flutter).
- **JDK 17** para compilar Android.
- **Android SDK** con las plataformas y *build-tools* correspondientes.

El proyecto se desarrolló y verificó con:

| Herramienta        | Versión        |
| ------------------ | -------------- |
| Flutter (stable)   | 3.47.7         |
| Dart               | 3.13.5         |
| JDK                | 17 (Microsoft OpenJDK 17.0.20) |
| Android compileSdk | 36             |
| Android minSdk     | 24             |
| Android targetSdk  | 36             |

---

## 6. Compilación e instalación

### 6.0 APK ya compilado (prueba rápida)

Si solo quieres probar la aplicación, hay un APK Release adjunto en la página de
*releases* del repositorio:

**<https://github.com/leomaresc/watap-mobile/releases/latest>**

Descarga `app-release.apk`, ábrelo en el teléfono y permite la instalación desde
orígenes desconocidos. Recuerda que ese APK está firmado con las **claves de
depuración** (ver [6.5](#65-firma-de-la-versión-release)).

### 6.1 Preparar el proyecto

```bash
flutter pub get
```

### 6.2 Ejecutar en un dispositivo o emulador

```bash
flutter run
```

### 6.3 Generar el APK Release

```bash
flutter build apk --release
```

El APK resultante queda en:

```
build/app/outputs/flutter-apk/app-release.apk
```

Instálalo con `adb`:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 6.4 Generar un App Bundle (opcional, para Google Play)

```bash
flutter build appbundle --release
```

El resultado queda en `build/app/outputs/bundle/release/app-release.aab`.

### 6.5 Firma de la versión Release

> ⚠️ **Importante:** tal como viene el repositorio, la compilación Release
> **se firma con las claves de depuración** (`signingConfigs.getByName("debug")`),
> que es la configuración por defecto del andamiaje de Flutter. Esto **sirve
> para instalar y probar el APK**, pero **no es apta para publicar en Google
> Play**.

Para firmar con tu propio *keystore*:

1. Crea un keystore (guárdalo **fuera** del control de versiones):

   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Crea `android/key.properties` (también fuera del control de versiones; ya está
   en `.gitignore`):

   ```properties
   storePassword=TU_CONTRASEÑA
   keyPassword=TU_CONTRASEÑA
   keyAlias=upload
   storeFile=/ruta/absoluta/a/upload-keystore.jks
   ```

3. Añade la configuración de firma en `android/app/build.gradle.kts` y sustituye
   `signingConfig = signingConfigs.getByName("debug")` por tu configuración de
   *release*.

La versión Release se compila además con `minifyEnabled` y
`shrinkResources`, y con reglas de ProGuard en
`android/app/proguard-rules.pro`.

---

## 7. Obtener una clave de Steam Web API

La aplicación **no incluye ninguna clave** y no funcionará con perfiles reales
sin una propia. Obtenerla es gratuito:

1. Inicia sesión en Steam en el navegador.
2. Visita la página oficial:
   **<https://steamcommunity.com/dev/apikey>**
3. Rellena el campo *Domain Name*. Para uso personal basta con un nombre de
   dominio cualquiera (por ejemplo, `localhost`); Steam no verifica la
   propiedad para este tipo de clave.
4. Acepta las condiciones y pulsa **Register**.
5. Copia la clave de 32 caracteres que aparece. **No la compartas**: identifica
   tu cuenta y tiene límites de uso.

> La clave se usa únicamente para llamar a la Steam Web API en nombre de tu
> cuenta. Cualquiera que la tenga puede consumir tu cuota de solicitudes.

---

## 8. Configurar la clave en la aplicación

1. Abre **Ajustes** (pestaña inferior derecha).
2. En la sección **STEAM WEB API**, toca **Sin clave configurada / Clave
   configurada**.
3. Pega la clave y guárdala.
4. Opcional: toca **Verificar la clave**. WATAP hará una consulta **real** a
   `GetPlayerSummaries` (usando tu perfil propio, si lo has marcado, o un perfil
   público conocido de Valve) y te dirá si Steam la acepta.

**Cómo se guarda la clave:**

- Se almacena **exclusivamente** en el almacenamiento seguro del dispositivo
  (Keystore en Android, Keychain en iOS) mediante `flutter_secure_storage`.
- **Nunca** se guarda en SQLite, ni en JSON, ni en preferencias, ni en recursos
  del APK, ni en registros.
- Viaja a Steam en el encabezado HTTP `x-webapi-key`, **nunca** en la URL, para
  que no quede en rutas ni en registros de intermediarios.

---

## 9. Conexión con Steam y grupo familiar

## 9. Conectar con Steam (grupo familiar)

El grupo familiar **no** se puede leer con la clave de Web API: Steam solo lo
entrega con un token de una sesión iniciada. WATAP obtiene ese token de la forma
menos invasiva posible:

1. En el asistente inicial (o en **Integrantes → Conectar con Steam**), la app
   abre la **página oficial de inicio de sesión de Steam** dentro de un WebView.
2. Tú escribes tu cuenta y contraseña **en la propia página de Valve**. WATAP
   no las ve, no las guarda y no las envía a ningún sitio.
3. Después del acceso, Steam redirige a un endpoint que devuelve un token
   temporal (`webapi_token`). WATAP lo guarda en el **almacenamiento seguro**
   del dispositivo (Keystore/Keychain).
4. Con ese token, WATAP llama a `IFamilyGroupsService/GetFamilyGroupForUser` y
   `GetFamilyGroup` para obtener el nombre de tu familia y sus integrantes.
5. Cada integrante se añade con su nombre público y avatar (gracias a la clave
   de Web API) y se marca como `isFamilyMember`.

### Cosas importantes

- **Si Steam no acepta el WebView** (a veces pide verificación adicional), puedes
  **omitir el paso** en el asistente y la app sigue funcionando: solo tendrás
  que importar integrantes a mano desde Integrantes. El paso se puede repetir
  más tarde desde Integrantes o Ajustes.
- **El token caduca**. Cuando eso pasa, WATAP borra el token y te pide conectar
  otra vez. Tus integrantes guardados **no se pierden**.
- **Los perfiles añadidos a mano nunca se borran** al sincronizar. Solo se
  retiran los que estaban en el grupo familiar y ya no lo están.
- **Si tu cuenta no tiene grupo familiar**, Steam lo indica y no se modifica
  nada.

### Advertencia sobre endpoints internos

`IFamilyGroupsService` **no está en la documentación pública de Valve**: es el
mismo endpoint que usa el cliente oficial de Steam y puede cambiar sin aviso.
WATAP interpreta sus respuestas de forma defensiva y muestra un error claro
(«error 405…») si Steam cambia el formato.

---

## 10. Uso de la aplicación

La barra de navegación inferior tiene cuatro secciones:

- **Recientes**: actividad por integrante. Incluye búsqueda, filtro por persona,
  ordenación y un interruptor para **ocultar juegos con poca actividad**.
- **General**: juegos **agregados por AppID**, con el desglose por integrante y
  las sumas totales del grupo.
- **Integrantes**: tarjeta del grupo familiar (conexión, sincronización y
  estado), lista de perfiles y, como respaldo, importación manual.
- **Ajustes**: conexión con Steam, clave de API, umbrales de actividad,
  visualización, caché y pantallas de privacidad y "Acerca de".

Acciones habituales:

- **Actualizar todo**: botón de refresco de la cabecera.
- **Actualizar un integrante**: botón de refresco de su tarjeta.
- **Sincronizar grupo familiar**: en la sección Integrentes; vuelve a leer tu
  familia en Steam y añade/retira integrantes automáticamente.
- **Abrir el juego en Steam**: icono de enlace de cada juego (abre la ficha en la
  tienda con la aplicación del sistema).
- **Borrar caché de actividad**: en Ajustes; elimina los datos de actividad y
  **conserva** la lista de integrantes.

---

## 11. Privacidad y datos almacenados

WATAP **no tiene servidores propios**. No hay cuentas, ni sincronización, ni
telemetría. Todo vive en tu dispositivo:

| Dato                                   | Dónde se guarda                         |
| -------------------------------------- | --------------------------------------- |
| Clave de Steam Web API                 | Almacenamiento seguro (Keystore/Keychain) |
| Token de sesión de Steam (`webapi_token`) | Almacenamiento seguro (Keystore/Keychain) |
| Perfiles (SteamID64, nombre, avatar)   | SQLite local                            |
| Actividad y juegos en caché            | SQLite local                            |
| Preferencias                           | SQLite local                            |
| Portadas y avatares                    | Caché de imágenes en disco              |

**Nunca se guarda**: tu contraseña de Steam (se escribe solo en la página de
Valve dentro del WebView), cookies de sesión ni el resto de la respuesta de la
página de Steam.

**Qué sale del dispositivo:** únicamente las solicitudes HTTPS a
`api.steampowered.com` (Steam Web API e `IFamilyGroupsService`), la carga de la
página oficial de Steam en el WebView y las descargas de imágenes del CDN
público de Steam. Nada más. La aplicación no contacta con ningún otro servicio.

Puedes vaciar los datos desde **Ajustes**:

- *Desconectar Steam*: borra el token de sesión. Los integrantes se conservan.
- *Borrar caché de actividad*: elimina actividad y juegos guardados, conserva los
  integrantes.
- *Borrar caché de imágenes*: elimina portadas y avatares descargados.
- *Eliminar integrante*: borra el perfil y, en cascada, su actividad y sus
  juegos.

> Transparencia: el almacenamiento seguro protege la clave **en reposo**. Ninguna
> aplicación cliente puede garantizar protección absoluta frente a un dispositivo
> comprometido, con *root* o con ejecución instrumentada.

---

## 12. Permisos

El manifiesto de Android declara **un único permiso**:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Es necesario para consultar la Steam Web API y descargar las imágenes del CDN.
**No** se solicitan almacenamiento, ubicación, cámara, contactos ni
notificaciones.

---

## 13. Endpoints de Steam utilizados

### Endpoints públicos y documentados (Steam Web API)

La clave viaja siempre en el encabezado `x-webapi-key`, nunca en la URL.

| Operación              | Endpoint                                              |
| ---------------------- | ----------------------------------------------------- |
| Juegos recientes       | `/IPlayerService/GetRecentlyPlayedGames/v1/`          |
| Resúmenes de perfiles  | `/ISteamUser/GetPlayerSummaries/v2/`                  |
| Resolver nombre        | `/ISteamUser/ResolveVanityURL/v1/`                    |

### Endpoints internos (exigen token de sesión)

Estos endpoints **no están en la documentación pública de Steam** y **no
aceptan la clave de Web API**: requieren el `webapi_token` de una sesión
iniciada. El token viaja en el cuerpo del `POST`, nunca en la URL.

| Operación                        | Endpoint                                            |
| -------------------------------- | --------------------------------------------------- |
| Grupo familiar de la cuenta      | `/IFamilyGroupsService/GetFamilyGroupForUser/v1/`   |
| Detalle del grupo (integrantes)  | `/IFamilyGroupsService/GetFamilyGroup/v1/`          |

**Advertencia**: son los mismos endpoints que usa el cliente oficial de Steam y
pueden cambiar o dejar de funcionar sin aviso. WATAP los interpreta de forma
defensiva y muestra un error claro si Steam cambia el formato.

**Página de token usada por el WebView**:
`https://store.steampowered.com/pointssummary/ajaxgetasyncconfig` — es una
página oficial de Steam que, con sesión iniciada, devuelve JSON con el token.

Imágenes (CDN público de Steam):

- Portada: `https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/header.jpg`
- Icono: `https://media.steampowered.com/steamcommunity/public/images/apps/{appid}/{hash}.jpg`

Documentación oficial: <https://steamcommunity.com/dev>

---

## 14. Arquitectura del código

Se usa **`ChangeNotifier` del propio SDK** (sin paquetes de gestión de estado
adicionales), expuesto con un `InheritedNotifier` (`AppScope`). La lógica de
negocio vive en servicios y repositorios; el controlador solo los coordina.

Capas:

- `lib/core/` — modelos de dominio, formateo, validación y constantes
  (funciones puras, sin dependencias de UI ni de red).
- `lib/data/` — red (`steam/`), almacenamiento local (`local/`) y repositorios
  (`repositories/`).
- `lib/services/` — agregación, datos de demostración y coordinador de
  actualizaciones.
- `lib/state/` — controlador de la aplicación y `AppScope`.
- `lib/features/` — pantallas, agrupadas por sección.
- `lib/widgets/` — componentes reutilizables.
- `lib/theme/` — tema oscuro inspirado en Steam (Material 3).

Puntos destacados:

- `SteamApiClient` exige HTTPS, aplica tiempos de espera, interpreta los códigos
  HTTP según el endpoint, respeta el `Retry-After` de un HTTP 429, **limita la
  concurrencia** y **deduplica** solicitudes idénticas en vuelo.
- `RefreshCoordinator` evita actualizaciones duplicadas, descarta respuestas
  tardías (generaciones) y conserva los datos anteriores ante un fallo.
- `ActivityRepository` implementa la política de caché (ver el apartado
  siguiente).

---

## 15. Modelo de datos y política de caché

**Regla central:** *los datos válidos no se reemplazan por resultados vacíos
derivados de un error.*

- Una **respuesta válida** (`ok` o `noRecentGames`) sustituye los juegos
  guardados y actualiza la marca de última consulta correcta.
- Un **fallo** (`networkError`, `privateOrUnavailable`, `rateLimited`, …) **conserva**
  los juegos anteriores si existían y los marca como procedentes de la caché
  (`fromCache` / `isStale`).
- Un valor **no comunicado por Steam** se representa como `null` y se muestra
  como **`—`**, nunca como `0`.
- Los **totales agregados** son `null` si falta algún dato, para no presentar un
  parcial como completo.

El esquema SQLite tiene **migraciones versionadas**
(`lib/data/local/database_migrations.dart`). El camino de migración se ejercita
también en instalaciones nuevas, de modo que no puede quedar obsoleto.

---

## 16. Pruebas automatizadas

Las pruebas **no realizan llamadas reales a Steam**: usan un cliente HTTP
simulado (`MockClient`) y una base de datos **SQLite en memoria** mediante
`sqflite_common_ffi` (sin emulador ni dispositivo).

Ejecuta toda la suite:

```bash
flutter test
```

Cobertura funcional de la suite:

- **Funciones puras**: formateo de minutos, números, fechas y tiempos relativos;
  clasificación de actividad; validación y normalización de entradas
  (SteamID64, URL, *vanity*, alias, umbrales y formato de clave).
- **Modelos de dominio**: totales con datos desconocidos, marca de demostración
  persistente y saneado de preferencias.
- **Agregación**: suma por AppID, acumulados incompletos, ordenaciones, filtros y
  búsqueda.
- **Red**: encabezado `x-webapi-key` (y ausencia de la clave en la URL), 429 con
  `Retry-After`, interpretación de 401/403 por endpoint, 400/500, JSON inválido,
  deduplicación y límite de concurrencia, y verificación de clave.
- **Parseo**: respuestas válidas, `{"response":{}}` como "no disponible",
  negativos saturados, datos ausentes como `null`, resolución de *vanity* y lista
  de amigos.
- **Almacenamiento local**: persistencia, prevención de duplicados, borrado en
  cascada, política de caché, migraciones desde la versión 1 y **aislamiento de
  la clave de API** (se comprueba que la clave no aparece en ninguna tabla).
- **Servicios**: datos de demostración (todo marcado como ficticio) y coordinador
  de actualizaciones (demostración sin red, privacidad, caché ante fallos y
  concurrencia del flujo).
- **Controlador**: modos de arranque, alta/duplicados/resolución de *vanity*,
  gestión de la clave, actualización y borrado de caché.
- **Widgets**: estados de carga, error y vacío, arranque en modo demostración sin
  red, navegación entre secciones y visualización de datos en caché.

Puedes ejecutar una parte concreta, por ejemplo:

```bash
flutter test test/data/steam_api_client_test.dart
```

---

## 17. Análisis estático

```bash
flutter analyze
```

El proyecto parte de `flutter_lints` con comprobaciones adicionales
(`strict-casts`, `strict-inference`, `strict-raw-types`, `avoid_print` como error,
`unawaited_futures` como aviso). **No se desactiva ninguna regla para "hacer
pasar" el análisis.**

---

## 18. Limitaciones conocidas

- **El APK Release se firma con claves de depuración** (ver
  [Firma de la versión Release](#65-firma-de-la-versión-release)). Es instalable
  y probable, pero **no publicable** en Google Play tal cual.
- **No se ha compilado ni probado en iOS** en este entorno: el andamiaje de iOS
  está incluido y el código evita dependencias no portables, pero no se ha
  generado un `.ipa` ni se ha ejecutado en un dispositivo Apple (requiere macOS y
  Xcode).
- **No se ha probado en un dispositivo Android físico** en el desarrollo de este
  repositorio; las verificaciones se hicieron con `flutter analyze`,
  `flutter test` y la compilación Release del APK.
- **Los límites de la Steam Web API son reales**: puede responder con HTTP 429.
  WATAP respeta el `Retry-After` (con un tope) y avisa en lugar de insistir.
- **Perfiles privados**: si los "Detalles del juego" del perfil son privados,
  Steam no entrega la actividad y WATAP no puede mostrarla (ni la inventa).
- **Importación de amigos**: la lista de amigos es privada por defecto; requiere
  marcarte como "mi perfil" y que la lista sea accesible para tu clave.

---

## 19. Hoja de ruta

- [ ] **Integración de anuncios** (prevista, **no implementada** todavía). Cuando
      se aborde, se hará con un formato no intrusivo (p. ej. un banner discreto
      fuera del contenido principal), respetando la sección de privacidad y sin
      afectar al modo demostración. Por ahora **la aplicación no contiene ningún
      SDK de publicidad ni código de anuncios**.
- [ ] Localización a otros idiomas (la interfaz está en español; el paquete
      `flutter_localizations` ya está integrado).
- [ ] Exportar/importar la lista de integrantes.
- [ ] Widgets de pantalla de inicio con el resumen del grupo.

---

## 20. Estructura del repositorio

```
.
├── android/                 # Proyecto Android (Gradle, manifiesto, ProGuard)
├── assets/                  # Recursos locales (images/, icons/)
├── ios/                     # Proyecto iOS (Generado por Flutter)
├── lib/
│   ├── core/                # Modelos, formateo, validación, constantes
│   ├── data/
│   │   ├── local/           # SQLite, migraciones, almacén seguro, caché
│   │   ├── repositories/    # Perfiles, actividad y preferencias
│   │   └── steam/           # Cliente HTTP, URLs, errores y parseo
│   ├── features/            # Pantallas por sección
│   ├── services/            # Agregación, demo y coordinador de refresco
│   ├── state/               # Controlador y AppScope
│   ├── theme/               # Tema oscuro (Material 3)
│   ├── widgets/             # Componentes reutilizables
│   ├── app.dart             # Composición de la app
│   └── main.dart            # Punto de entrada
├── test/                    # Pruebas automatizadas (sin red real)
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

---

## 21. Licencia y descargos

Este proyecto se distribuye bajo la **licencia MIT**. Consulta el archivo
[`LICENSE`](LICENSE).

**Descargo de responsabilidad:**

- WATAP Mobile es un proyecto **independiente** y **no está afiliado, asociado,
  autorizado, respaldado ni vinculado** de ninguna forma oficial con Valve
  Corporation ni con Steam. Steam es una marca registrada de Valve Corporation.
- Los datos mostrados **pertenecen a Steam** y se obtienen exclusivamente a
  través de su Web API pública y documentada y de su CDN público de imágenes.
- El uso de la Steam Web API está sujeto a las
  [condiciones de Valve](https://steamcommunity.com/dev/apiterms). Eres
  responsable de cumplirlas y de proteger tu propia clave de API.

