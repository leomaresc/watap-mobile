/// Cliente de `IFamilyGroupsService`: el grupo familiar de Steam.
///
/// **Este servicio solo acepta el `access_token` de una sesión de Steam**
/// iniciada (el `webapi_token` de la sesión de la tienda).
///
/// Steam exige **GET** para este servicio: el `POST` responde HTTP 405
/// («This API must be called with a HTTP GET request»). Por eso el token viaja
/// como parámetro `access_token` de la URL, sobre una conexión HTTPS directa a
/// `api.steampowered.com`, y nunca se escribe en un registro.
///
/// Es un endpoint **interno** (no documentado por Valve), por lo que todas las
/// respuestas se interpretan de forma defensiva.
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

  /// Consulta el identificador del grupo familiar de la cuenta autenticada.
  Future<FamilyGroupForUser> getFamilyGroupForUser(String accessToken) async {
    final String body = await _get(
      SteamApiUrls.familyGroupForUser(accessToken),
      endpoint: 'GetFamilyGroupForUser',
    );
    return parseFamilyGroupForUser(body);
  }

  /// Consulta el nombre y los integrantes de un grupo familiar concreto.
  Future<FamilyGroup> getFamilyGroup({
    required String accessToken,
    required String familyGroupId,
  }) async {
    final String body = await _get(
      SteamApiUrls.familyGroup(accessToken, familyGroupId),
      endpoint: 'GetFamilyGroup',
    );
    return parseFamilyGroup(body, familyGroupId: familyGroupId);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  // -------------------------------------------------------------------------

  /// Envía un `GET` con los parámetros ya incluidos en la URL.
  ///
  /// Steam exige `GET` en este servicio. Se exige HTTPS y se aplica un tiempo
  /// de espera finito.
  Future<String> _get(
    Uri uri, {
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
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
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
      if (_tokenRejected(body)) {
        throw SteamApiException(
          kind: SteamApiErrorKind.invalidCredentials,
          messageEs: 'El token de Steam ha caducado o no es válido. Vuelve a '
              'conectar tu cuenta para obtener uno nuevo.',
          endpoint: endpoint,
        );
      }
      return body;
    }

    throw _mapHttpError(response.statusCode, endpoint);
  }

  SteamApiException _mapHttpError(int statusCode, String endpoint) {
    switch (statusCode) {
      case 401:
      case 403:
        return SteamApiException(
          kind: SteamApiErrorKind.invalidCredentials,
          messageEs: 'Steam ha rechazado el token de sesión. Vuelve a conectar '
              'tu cuenta de Steam para obtener uno nuevo.',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      case 405:
        return SteamApiException(
          kind: SteamApiErrorKind.http,
          messageEs: 'Steam no admite esta operación (error 405). Es posible '
              'que los endpoints internos hayan cambiado.',
          statusCode: statusCode,
          endpoint: endpoint,
        );
      case 429:
        return SteamApiException(
          kind: SteamApiErrorKind.rateLimited,
          messageEs: defaultSteamErrorMessage(SteamApiErrorKind.rateLimited),
          statusCode: statusCode,
          endpoint: endpoint,
        );
      default:
        if (statusCode >= 500) {
          return SteamApiException(
            kind: SteamApiErrorKind.http,
            messageEs: 'Steam no está disponible en este momento '
                '(error $statusCode). Inténtalo de nuevo más tarde.',
            statusCode: statusCode,
            endpoint: endpoint,
          );
        }
        return SteamApiException(
          kind: SteamApiErrorKind.http,
          messageEs: 'Steam devolvió un error inesperado ($statusCode) al '
              'consultar el grupo familiar.',
          statusCode: statusCode,
          endpoint: endpoint,
        );
    }
  }

  /// `true` cuando Steam responde 200 pero rechaza el token dentro del cuerpo.
  ///
  /// `eresult` 5 (InvalidPassword) y 15/21 (Expired) indican un token vencido.
  static bool _tokenRejected(String body) {
    final String trimmed = body.trim();
    if (!trimmed.startsWith('{')) return false;
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is! Map) return false;
      final Object? eresult = decoded['eresult'];
      final int? code = eresult is int
          ? eresult
          : (eresult is String ? int.tryParse(eresult) : null);
      return code == 5 || code == 15 || code == 21;
    } on FormatException {
      return false;
    }
  }
}
