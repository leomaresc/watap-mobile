/// Cliente de `IFamilyGroupsService`: el grupo familiar de Steam.
///
/// **Este servicio no funciona con una clave de Web API.** Steam solo lo expone
/// a sesiones iniciadas, por lo que cada solicitud lleva el `access_token` de
/// `SteamAuthClient` en el cuerpo del `POST` (nunca en la URL).
///
/// Endpoints internos, no documentados por Valve: se interpretan de forma
/// defensiva y cualquier cambio de formato produce un error explícito.
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

/// Cliente del grupo familiar de Steam.
class FamilyGroupsClient {
  FamilyGroupsClient({
    http.Client? httpClient,
    Duration timeout = AppConstants.requestTimeout,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _timeout = timeout;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  /// Obtiene el grupo familiar de la cuenta autenticada.
  Future<FamilyGroupForUser> getFamilyGroupForUser(String accessToken) async {
    final String body = await _post(
      SteamApiUrls.familyGroupForUser(),
      <String, String>{'access_token': accessToken},
      endpoint: 'GetFamilyGroupForUser',
    );
    return parseFamilyGroupForUser(body);
  }

  /// Obtiene el detalle (nombre e integrantes) de un grupo familiar.
  Future<FamilyGroup> getFamilyGroup({
    required String accessToken,
    required String familyGroupId,
  }) async {
    final String body = await _post(
      SteamApiUrls.familyGroup(),
      <String, String>{
        'access_token': accessToken,
        'family_groupid': familyGroupId,
      },
      endpoint: 'GetFamilyGroup',
    );
    return parseFamilyGroup(body, familyGroupId: familyGroupId);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // -------------------------------------------------------------------------

  Future<String> _post(
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

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Un 401 con cuerpo JSON suele indicar que el token ha caducado.
      if (_looksLikeExpiredToken(body)) {
        throw SteamApiException(
          kind: SteamApiErrorKind.invalidCredentials,
          messageEs: 'La sesión de Steam ha caducado. Vuelve a iniciar sesión '
              'para consultar el grupo familiar.',
          statusCode: response.statusCode,
          endpoint: endpoint,
        );
      }
      return body;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SteamApiException(
        kind: SteamApiErrorKind.invalidCredentials,
        messageEs: 'Steam no ha aceptado la sesión. Vuelve a iniciar sesión.',
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    }
    if (response.statusCode == 429) {
      throw SteamApiException(
        kind: SteamApiErrorKind.rateLimited,
        messageEs: defaultSteamErrorMessage(SteamApiErrorKind.rateLimited),
        statusCode: response.statusCode,
        endpoint: endpoint,
      );
    }
    throw SteamApiException(
      kind: SteamApiErrorKind.http,
      messageEs: 'Steam devolvió un error inesperado '
          '(${response.statusCode}) al consultar el grupo familiar.',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  /// `true` cuando Steam señala un token caducado (suele acompañarlo de
  /// `eresult` 21 = `Expired`).
  static bool _looksLikeExpiredToken(String body) {
    final String trimmed = body.trim();
    if (!trimmed.startsWith('{')) return false;
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final Object? value = decoded['eresult'];
        final int? code =
            value is int ? value : (value is String ? int.tryParse(value) : null);
        if (code == 21 || code == 5 || code == 15) return true;
        // `{"response":{}}` sin datos tampoco permite continuar.
        final Object? response = decoded['response'];
        if (response is Map && response.isEmpty && code == null) {
          return decoded['error'] != null;
        }
      }
    } on FormatException {
      return false;
    }
    return false;
  }
}
