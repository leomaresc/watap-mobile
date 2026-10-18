/// Inicio de sesión en Steam para obtener un `access_token`.
///
/// **Por qué es necesario.** El grupo familiar no se puede consultar con una
/// clave de Web API: `IFamilyGroupsService` solo acepta el `access_token` de una
/// sesión de Steam iniciada. Para conseguirlo se reproduce el mismo flujo que
/// usa el cliente oficial (`IAuthenticationService`), cifrando la contraseña
/// con la clave pública RSA que entrega Steam.
///
/// **Qué se hace con la contraseña.** Se cifra en memoria con la clave pública
/// de Steam y se envía directamente a `api.steampowered.com`. Nunca se guarda,
/// nunca se registra y nunca se incluye en un mensaje de error. Lo que sí se
/// guarda (en el almacenamiento seguro del dispositivo, ver
/// `SteamSessionStore`) es el `refresh_token`, que permite renovar el acceso
/// sin volver a escribir la contraseña.
///
/// **Estado.** Estos endpoints no están en la documentación pública de Valve;
/// son los mismos que usa el cliente de Steam y pueden cambiar sin aviso. Por
/// eso todas las respuestas se interpretan de forma defensiva y cualquier
/// cambio de formato se convierte en un error claro en lugar de un fallo
/// silencioso.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/models.dart';
import 'steam_api_errors.dart';
import 'steam_api_urls.dart';
import 'steam_json_parsers.dart';
import 'steam_rsa.dart';

/// Paso intermedio del inicio de sesión.
///
/// Steam puede exigir un código de Steam Guard (por correo o generado por la
/// aplicación móvil) antes de entregar la sesión.
class SteamLoginChallenge {
  const SteamLoginChallenge({
    required this.clientId,
    required this.requestId,
    required this.steamId64,
    required this.pollInterval,
    required this.needsGuardCode,
    this.guardCodeIsEmail = false,
    this.steamMessage,
    required this.accountName,
  });

  final String clientId;
  final String requestId;
  final String steamId64;
  final Duration pollInterval;

  /// `true` cuando hay que pedir el código al usuario.
  final bool needsGuardCode;

  /// `true` cuando el código llega por correo (y no lo genera la app móvil).
  final bool guardCodeIsEmail;

  /// Mensaje informativo de Steam (por ejemplo, el correo al que envió el
  /// código). Nunca contiene secretos.
  final String? steamMessage;

  /// Nombre de la cuenta con la que se está iniciando sesión.
  final String accountName;
}

/// Cliente del servicio de autenticación de Steam.
class SteamAuthClient {
  SteamAuthClient({
    http.Client? httpClient,
    Duration timeout = AppConstants.requestTimeout,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _timeout = timeout;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  /// Inicia el acceso con cuenta y contraseña.
  ///
  /// Devuelve el desafío que indica si hace falta un código de Steam Guard. La
  /// contraseña se usa solo para construir la solicitud cifrada.
  Future<SteamLoginChallenge> beginLogin({
    required String accountName,
    required String password,
  }) async {
    final String account = accountName.trim();
    if (account.isEmpty || password.isEmpty) {
      throw const SteamApiException(
        kind: SteamApiErrorKind.incompleteConfiguration,
        messageEs: 'Escribe la cuenta y la contraseña de Steam.',
      );
    }

    final PasswordRsaKeyParse rsaKey = await _fetchPasswordRsaKey(account);
    final String encrypted = rsaEncryptPassword(
      SteamRsaPublicKey(
        modulusHex: rsaKey.modulusHex,
        exponentHex: rsaKey.exponentHex,
      ),
      password,
    );

    final String body = await _postForm(
      SteamApiUrls.authService(SteamApiEndpoints.beginAuthSession),
      <String, String>{
        'account_name': account,
        'encrypted_password': encrypted,
        'encryption_timestamp': '${rsaKey.timestamp}',
        'remember_login': 'true',
        'platform_type': AppConstants.steamLoginPlatformType,
        'persistence': '1',
        'website_id': 'Community',
        'device_friendly_name': AppConstants.steamLoginDeviceName,
      },
      endpoint: 'BeginAuthSessionViaCredentials',
    );

    final BeginAuthSessionParse parsed = parseBeginAuthSession(body);
    final bool needsCode = parsed.needsCode;
    return SteamLoginChallenge(
      clientId: parsed.clientId,
      requestId: parsed.requestId,
      steamId64: parsed.steamId64 ?? '',
      pollInterval: Duration(seconds: parsed.intervalSeconds),
      needsGuardCode: needsCode,
      guardCodeIsEmail:
          needsCode && !parsed.confirmationTypes.contains(3),
      steamMessage: parsed.confirmationMessage,
      accountName: account,
    );
  }

  /// Entrega el código de Steam Guard y espera a que Steam confirme la sesión.
  Future<SteamSession> submitGuardCode({
    required SteamLoginChallenge challenge,
    required String code,
  }) async {
    final String trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw const SteamApiException(
        kind: SteamApiErrorKind.incompleteConfiguration,
        messageEs: 'Escribe el código de Steam Guard.',
      );
    }
    // `code_type`: 2 = código enviado por correo, 3 = código de la app móvil.
    final String codeType = challenge.guardCodeIsEmail ? '2' : '3';
    await _postForm(
      SteamApiUrls.authService(SteamApiEndpoints.updateAuthSessionWithGuardCode),
      <String, String>{
        'client_id': challenge.clientId,
        'steamid': challenge.steamId64,
        'code': trimmed,
        'code_type': codeType,
      },
      endpoint: 'UpdateAuthSessionWithSteamGuardCode',
    );
    return pollStatus(challenge);
  }

  /// Consulta el estado del acceso hasta que Steam entregue la sesión.
  ///
  /// Cuando Steam confirma desde el móvil (sin código), no hay nada que enviar:
  /// basta con esperar. Se respeta el intervalo que indica Steam.
  Future<SteamSession> pollStatus(
    SteamLoginChallenge challenge, {
    int maxAttempts = AppConstants.steamLoginMaxPollAttempts,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(challenge.pollInterval);
      final String body = await _postForm(
        SteamApiUrls.authService(SteamApiEndpoints.pollAuthSessionStatus),
        <String, String>{
          'client_id': challenge.clientId,
          'request_id': challenge.requestId,
        },
        endpoint: 'PollAuthSessionStatus',
      );
      final PollAuthSessionParse parsed = parsePollAuthSession(body);
      if (parsed.isComplete) {
        return SteamSession(
          steamId64: challenge.steamId64,
          accessToken: parsed.accessToken!,
          refreshToken: parsed.refreshToken!,
          accountName: parsed.accountName ?? challenge.accountName,
          savedAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
      }
    }
    throw const SteamApiException(
      kind: SteamApiErrorKind.timeout,
      messageEs: 'Steam no ha confirmado el acceso. Si tienes activada la '
          'confirmación por aplicación móvil, acéptala en tu teléfono y vuelve '
          'a intentarlo.',
      endpoint: 'PollAuthSessionStatus',
    );
  }

  /// Renueva el `access_token` a partir del `refresh_token` guardado.
  ///
  /// Se usa cuando una consulta con el token actual falla por caducidad.
  Future<SteamSession> refreshSession(SteamSession session) async {
    final String body = await _postForm(
      SteamApiUrls.authService(SteamApiEndpoints.generateAccessTokenForApp),
      <String, String>{
        'refresh_token': session.refreshToken,
        'steamid': session.steamId64,
      },
      endpoint: 'GenerateAccessTokenForApp',
    );
    final String? token = parseGenerateAccessToken(body);
    if (token == null) {
      throw const SteamApiException(
        kind: SteamApiErrorKind.invalidCredentials,
        messageEs: 'La sesión de Steam ha caducado. Vuelve a iniciar sesión.',
        endpoint: 'GenerateAccessTokenForApp',
      );
    }
    return session.copyWith(
      accessToken: token,
      savedAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // -------------------------------------------------------------------------

  Future<PasswordRsaKeyParse> _fetchPasswordRsaKey(String accountName) async {
    final String body = await _postForm(
      SteamApiUrls.authService(SteamApiEndpoints.passwordRsaPublicKey),
      <String, String>{'account_name': accountName},
      endpoint: 'GetPasswordRSAPublicKey',
    );
    return parsePasswordRsaPublicKey(body);
  }

  /// Envía una solicitud `POST` con campos de formulario.
  ///
  /// Los secretos (contraseña cifrada, tokens) viajan en el **cuerpo**, nunca en
  /// la URL. Se exige HTTPS y se aplica un tiempo de espera finito.
  Future<String> _postForm(
    Uri uri,
    Map<String, String> fields, {
    required String endpoint,
  }) async {
    if (uri.scheme != 'https') {
      throw SteamApiException(
        kind: SteamApiErrorKind.unknown,
        messageEs: 'Por seguridad, WATAP solo realiza solicitudes HTTPS.',
        endpoint: endpoint,
      );
    }

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: fields,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw SteamApiException(
        kind: SteamApiErrorKind.timeout,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.timeout),
        endpoint: endpoint,
      );
    } on SocketException {
      throw SteamApiException(
        kind: SteamApiErrorKind.network,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.network),
        endpoint: endpoint,
      );
    } on http.ClientException {
      throw SteamApiException(
        kind: SteamApiErrorKind.network,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.network),
        endpoint: endpoint,
      );
    } on HandshakeException {
      throw SteamApiException(
        kind: SteamApiErrorKind.network,
        messageEs: 'No se pudo establecer una conexión segura con Steam.',
        endpoint: endpoint,
      );
    }

    final String body = response.body.isNotEmpty
        ? response.body
        : utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapHttpError(response.statusCode, body, endpoint);
    }

    // Steam puede responder 200 con un `eresult` distinto de 1.
    final int? eresult = _extractEResult(body);
    if (eresult != null && eresult != 1) {
      throw _mapEResult(eresult, endpoint);
    }
    return body;
  }

  static int? _extractEResult(String body) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final Object? value = decoded['eresult'];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  SteamApiException _mapHttpError(int statusCode, String body, String endpoint) {
    switch (statusCode) {
      case 429:
        return SteamApiException(
          kind: SteamApiErrorKind.rateLimited,
          messageEs: defaultSteamErrorMessage(SteamApiErrorKind.rateLimited),
          statusCode: statusCode,
          endpoint: endpoint,
        );
      case 401:
      case 403:
        return SteamApiException(
          kind: SteamApiErrorKind.invalidCredentials,
          messageEs: 'Steam ha rechazado el acceso. Comprueba la cuenta y la '
              'contraseña.',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      default:
        return SteamApiException(
          kind: SteamApiErrorKind.http,
          messageEs: 'Steam devolvió un error inesperado ($statusCode) al '
              'iniciar sesión.',
          statusCode: statusCode,
          endpoint: endpoint,
        );
    }
  }

  /// Traduce los códigos `EResult` conocidos a mensajes en español.
  ///
  /// Fuente: valores públicos del `EResult` de Steam. Los no reconocidos se
  /// presentan como un fallo genérico sin inventar causas.
  SteamApiException _mapEResult(int eresult, String endpoint) {
    final String message = switch (eresult) {
      5 => 'La cuenta o la contraseña no son correctas.',
      63 => 'Steam pide un código de Steam Guard para esta cuenta.',
      65 => 'La solicitud de acceso ha caducado. Vuelve a intentarlo.',
      84 => defaultSteamErrorMessage(SteamApiErrorKind.rateLimited),
      85 => 'Demasiados intentos de acceso. Espera unos minutos antes de '
          'volver a probar.',
      88 => 'El código de Steam Guard no es correcto.',
      _ => 'Steam no ha completado el acceso (código $eresult).',
    };
    final bool credentials = eresult == 5 || eresult == 88;
    return SteamApiException(
      kind: credentials
          ? SteamApiErrorKind.invalidCredentials
          : SteamApiErrorKind.http,
      messageEs: message,
      endpoint: endpoint,
    );
  }
}
