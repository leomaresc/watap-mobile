/// Pruebas de las funciones puras de formateo y clasificación.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:watap_mobile/core/formatters.dart';
import 'package:watap_mobile/core/models.dart';

void main() {
  group('formatMinutes', () {
    test('un dato no comunicado se muestra como guion, nunca como cero', () {
      expect(formatMinutes(null), kUnknownValue);
    });

    test('formatea minutos, horas y combinaciones', () {
      expect(formatMinutes(0), '0 min');
      expect(formatMinutes(-5), '0 min');
      expect(formatMinutes(45), '45 min');
      expect(formatMinutes(60), '1 h');
      expect(formatMinutes(120), '2 h');
      expect(formatMinutes(515), '8 h 35 min');
    });
  });

  group('formatMinutesWithSuffix', () {
    test('conserva el guion y añade el sufijo solo a valores conocidos', () {
      expect(formatMinutesWithSuffix(45, suffix: '!'), '45 min!');
      expect(formatMinutesWithSuffix(null, suffix: '!'), kUnknownValue);
      expect(formatMinutesWithSuffix(40), '40 min');
    });
  });

  group('formatNumber', () {
    test('usa separador de miles y respeta el signo', () {
      expect(formatNumber(null), kUnknownValue);
      expect(formatNumber(0), '0');
      expect(formatNumber(999), '999');
      expect(formatNumber(1000), '1.000');
      expect(formatNumber(1234567), '1.234.567');
      expect(formatNumber(-1234), '-1.234');
    });
  });

  group('formatLocalDateTime', () {
    test('devuelve guion cuando no hay fecha', () {
      expect(formatLocalDateTime(null), kUnknownValue);
      expect(formatLocalDateTime(0), kUnknownValue);
    });

    test('respeta el formato dd/MM/aaaa HH:mm', () {
      expect(
        formatLocalDateTime(1600000000),
        matches(RegExp(r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$')),
      );
    });
  });

  group('formatRelativeTime', () {
    final DateTime now = DateTime(2026, 1, 1, 12, 0, 0);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;

    test('sin fecha devuelve "nunca"', () {
      expect(formatRelativeTime(null, now: now), 'nunca');
      expect(formatRelativeTime(0, now: now), 'nunca');
    });

    test('describe cada tramo', () {
      expect(
        formatRelativeTime(ago(const Duration(seconds: 30)), now: now),
        'hace unos segundos',
      );
      expect(
        formatRelativeTime(ago(const Duration(minutes: 5)), now: now),
        'hace 5 min',
      );
      expect(
        formatRelativeTime(ago(const Duration(hours: 3)), now: now),
        'hace 3 h',
      );
      expect(
        formatRelativeTime(ago(const Duration(days: 4)), now: now),
        'hace 4 d',
      );
      expect(
        formatRelativeTime(ago(const Duration(days: 35)), now: now),
        'hace 1 mes',
      );
      expect(
        formatRelativeTime(ago(const Duration(days: 70)), now: now),
        'hace 2 meses',
      );
      expect(
        formatRelativeTime(ago(const Duration(days: 400)), now: now),
        'hace 1 año',
      );
    });

    test('una fecha futura se marca como tal', () {
      final int future = now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      expect(formatRelativeTime(future, now: now), 'en el futuro');
    });
  });

  group('classifyActivityMinutes', () {
    test('sin minutos conocidos no se asigna nivel', () {
      expect(
        classifyActivityMinutes(null, moderateThreshold: 120, highThreshold: 480),
        isNull,
      );
    });

    test('clasifica según los umbrales', () {
      expect(
        classifyActivityMinutes(0, moderateThreshold: 120, highThreshold: 480),
        ActivityLevel.none,
      );
      expect(
        classifyActivityMinutes(10, moderateThreshold: 120, highThreshold: 480),
        ActivityLevel.low,
      );
      expect(
        classifyActivityMinutes(119, moderateThreshold: 120, highThreshold: 480),
        ActivityLevel.low,
      );
      expect(
        classifyActivityMinutes(120, moderateThreshold: 120, highThreshold: 480),
        ActivityLevel.moderate,
      );
      expect(
        classifyActivityMinutes(479, moderateThreshold: 120, highThreshold: 480),
        ActivityLevel.moderate,
      );
      expect(
        classifyActivityMinutes(480, moderateThreshold: 120, highThreshold: 480),
        ActivityLevel.high,
      );
    });

    test('corrige un umbral alto inválido', () {
      expect(
        classifyActivityMinutes(120, moderateThreshold: 120, highThreshold: 0),
        ActivityLevel.moderate,
      );
      expect(
        classifyActivityMinutes(200, moderateThreshold: 120, highThreshold: 0),
        ActivityLevel.high,
      );
    });
  });

  group('etiquetas de nivel y estado', () {
    test('describeActivityLevel cubre todos los casos', () {
      expect(describeActivityLevel(null), 'Actividad no determinada');
      expect(describeActivityLevel(ActivityLevel.none), 'Sin actividad registrada');
      expect(describeActivityLevel(ActivityLevel.low), 'Actividad baja');
      expect(describeActivityLevel(ActivityLevel.moderate), 'Actividad moderada');
      expect(describeActivityLevel(ActivityLevel.high), 'Actividad alta');
    });

    test('describeFetchStatus distingue privado de sin juegos', () {
      expect(
        describeFetchStatus(FetchStatus.noRecentGames),
        'Steam no comunica juegos en las últimas dos semanas',
      );
      expect(
        describeFetchStatus(FetchStatus.privateOrUnavailable),
        'El perfil es privado o sus datos no están disponibles',
      );
    });

    test('explainFetchStatus solo aclara los estados ambiguos', () {
      expect(explainFetchStatus(FetchStatus.ok), isEmpty);
      expect(explainFetchStatus(FetchStatus.noRecentGames), isNotEmpty);
      expect(explainFetchStatus(FetchStatus.privateOrUnavailable), isNotEmpty);
    });

    test('activityLevelColorValue no lanza para ningún valor', () {
      for (final ActivityLevel? level in <ActivityLevel?>[...ActivityLevel.values, null]) {
        expect(activityLevelColorValue(level), isA<int>());
      }
    });
  });

  group('describeCacheOrigin', () {
    test('distingue datos actuales, caché y caché obsoleta', () {
      expect(
        describeCacheOrigin(fromCache: false, isStale: false, lastSuccessAtUnix: null),
        'Actualizado',
      );
      expect(
        describeCacheOrigin(fromCache: true, isStale: false, lastSuccessAtUnix: null),
        'Desde caché (nunca)',
      );
      expect(
        describeCacheOrigin(fromCache: false, isStale: true, lastSuccessAtUnix: null),
        'Caché desactualizada (nunca)',
      );
    });
  });

  group('isStaleTimestamp', () {
    final DateTime now = DateTime(2026, 1, 1, 12, 0, 0);

    test('una marca ausente se considera obsoleta', () {
      expect(isStaleTimestamp(null, now: now), isTrue);
      expect(isStaleTimestamp(0, now: now), isTrue);
    });

    test('aplica el límite de antigüedad', () {
      final int fresh =
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final int old =
          now.subtract(const Duration(hours: 7)).millisecondsSinceEpoch ~/ 1000;
      expect(isStaleTimestamp(fresh, now: now), isFalse);
      expect(isStaleTimestamp(old, now: now), isTrue);
    });
  });
}
