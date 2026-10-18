/// Pruebas de la validación y normalización de entradas.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/validators.dart';

void main() {
  group('isValidSteamId64', () {
    test('acepta 17 dígitos y rechaza el resto', () {
      expect(isValidSteamId64('76561198000000000'), isTrue);
      expect(isValidSteamId64('90000000000000001'), isTrue);
      expect(isValidSteamId64('123'), isFalse);
      expect(isValidSteamId64('7656119800000000x'), isFalse);
      expect(isValidSteamId64('00000000000000000'), isFalse);
    });
  });

  group('looksLikeIndividualSteamId64', () {
    test('reconoce las cuentas personales habituales', () {
      expect(looksLikeIndividualSteamId64('76561198000000000'), isTrue);
      expect(looksLikeIndividualSteamId64('90000000000000001'), isFalse);
    });
  });

  group('isValidVanityName', () {
    test('acepta letras, dígitos, guion y guion bajo', () {
      expect(isValidVanityName('nombrePersonalizado'), isTrue);
      expect(isValidVanityName('jugador_1-2'), isTrue);
      expect(isValidVanityName('a'), isFalse);
      expect(isValidVanityName('con espacio'), isFalse);
    });
  });

  group('normalizeProfileInput', () {
    test('extrae el SteamID64 de una URL de perfil', () {
      expect(
        normalizeProfileInput('https://steamcommunity.com/profiles/76561198000000000'),
        '76561198000000000',
      );
    });

    test('extrae el nombre personalizado de una URL /id', () {
      expect(
        normalizeProfileInput('https://steamcommunity.com/id/nombrePersonalizado'),
        'nombrePersonalizado',
      );
    });

    test('admite URL sin esquema y quita la barra final', () {
      expect(
        normalizeProfileInput('steamcommunity.com/id/nombre'),
        'nombre',
      );
      expect(normalizeProfileInput('nombre/'), 'nombre');
    });

    test('limpia caracteres invisibles pegados', () {
      expect(normalizeProfileInput('\u200Bnombre\uFEFF'), 'nombre');
    });
  });

  group('parseProfileInput', () {
    test('reconoce un SteamID64', () {
      final ProfileInputResult result = parseProfileInput('76561198000000000');
      expect(result.isValid, isTrue);
      expect(result.input!.kind, ProfileInputKind.steamId64);
      expect(result.input!.value, '76561198000000000');
    });

    test('reconoce un nombre personalizado', () {
      final ProfileInputResult result = parseProfileInput('jugador_1');
      expect(result.isValid, isTrue);
      expect(result.input!.kind, ProfileInputKind.vanity);
    });

    test('rechaza una entrada vacía con un mensaje útil', () {
      final ProfileInputResult result = parseProfileInput('   ');
      expect(result.isValid, isFalse);
      expect(result.errorEs, contains('Introduce'));
    });

    test('rechaza un SteamID64 de solo ceros', () {
      final ProfileInputResult result = parseProfileInput('00000000000000000');
      expect(result.isValid, isFalse);
      expect(result.errorEs, contains('ceros'));
    });

    test('rechaza nombres con espacios', () {
      final ProfileInputResult result = parseProfileInput('dos palabras');
      expect(result.isValid, isFalse);
      expect(result.errorEs, contains('espacios'));
    });

    test('rechaza enlaces de otros dominios', () {
      final ProfileInputResult result =
          parseProfileInput('https://example.com/id/algo');
      expect(result.isValid, isFalse);
      expect(result.errorEs, contains('steamcommunity.com'));
    });
  });

  group('validateAlias', () {
    test('acepta vacío y rechaza demasiado largo', () {
      expect(validateAlias(null), isNull);
      expect(validateAlias('   '), isNull);
      expect(validateAlias('a' * 40), isNull);
      expect(validateAlias('a' * 41), isNotNull);
    });
  });

  group('validateThreshold', () {
    test('valida el rango permitido', () {
      expect(validateThreshold(30, label: 'El umbral'), isNull);
      expect(validateThreshold(null, label: 'El umbral'), isNotNull);
      expect(validateThreshold(-1, label: 'El umbral'), isNotNull);
      expect(validateThreshold(600001, label: 'El umbral'), isNotNull);
    });
  });

  group('validateActivityThresholds', () {
    test('exige moderado positivo y menor que alto', () {
      expect(validateActivityThresholds(120, 480), isNull);
      expect(validateActivityThresholds(0, 480), isNotNull);
      expect(validateActivityThresholds(480, 480), isNotNull);
      expect(validateActivityThresholds(600, 100), isNotNull);
      expect(validateActivityThresholds(120, 600001), isNotNull);
    });
  });

  group('validateApiKeyFormat', () {
    test('detecta errores evidentes sin validar el contenido real', () {
      expect(validateApiKeyFormat(null), isNull);
      expect(validateApiKeyFormat(''), isNotNull);
      expect(validateApiKeyFormat('corta'), isNotNull);
      expect(validateApiKeyFormat('a' * 200), isNotNull);
      expect(validateApiKeyFormat('clave con espacios'), isNotNull);
      expect(validateApiKeyFormat('a' * 32), isNull);
    });
  });
}
