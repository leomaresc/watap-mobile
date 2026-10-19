/// Asistente de configuración inicial.
///
/// **Un solo paso**: conectar la cuenta de Steam mediante la página oficial de
/// Valve dentro de un WebView. Con el token resultante la app:
/// - lee el grupo familiar (`IFamilyGroupsService`) e importa los
///   integrantes solos;
/// - consulta la actividad de cada uno (`GetRecentlyPlayedGames`).
///
/// No se pide una clave de Web API ni enlaces manuales. Por eso se ofrece la
/// clave únicamente como **respaldo** (si la página de Steam no carga), y un
/// botón para omitir el paso de forma explícita: la aplicación nunca debe
/// quedar bloqueada.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';
import '../settings/api_key_screen.dart';
import 'steam_connect_screen.dart';

/// Pantalla de configuración inicial.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
    final bool connected = controller.hasFamilyToken;
    final bool hasKey = controller.hasApiKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración inicial'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const Text(
            'Un solo paso',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: WatapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Conecta tu cuenta de Steam y WATAP leerá tu grupo familiar y la '
            'actividad de sus integrantes: se añaden solos, con nombre y '
            'avatar. No hace falta pedir una clave de API ni copiar enlaces.',
            style: TextStyle(
              fontSize: 13,
              color: WatapColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          _StepCard(
            index: 1,
            title: 'Conectar con Steam',
            description:
                'Se abre la página oficial de inicio de sesión de Steam dentro '
                'de la app. Tu contraseña va directamente a Valve: WATAP no la '
                've ni la guarda. Después se leen tu familia y su actividad '
                'con un token temporal.',
            done: connected || hasKey,
            doneText: connected
                ? 'Conectado. Tu grupo familiar se puede sincronizar.'
                : 'Clave de API guardada (modo respaldo). El grupo familiar '
                    'se leerá cuando conectes Steam.',
            pendingText: 'Pendiente de conexión.',
            actionLabel: connected ? 'Volver a conectar' : 'Conectar con Steam',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const SteamConnectScreen(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (connected)
            const InlineNotice(
              message: 'Todo listo. Tus integrantes del grupo familiar se han '
                  'importado automáticamente y su actividad se consulta con el '
                  'mismo token.',
              icon: Icons.check_circle_outline,
              color: WatapColors.success,
            )
          else ...<Widget>[
            const InlineNotice(
              message: 'Solo se guarda un token temporal en el almacén seguro '
                  'del dispositivo. Nunca se escribe en la base de datos, en '
                  'archivos ni en la nube.',
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _skip(context),
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('Omitir el paso por ahora'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const ApiKeyScreen(),
                ),
              ),
              icon: const Icon(Icons.key_outlined, size: 18),
              label: const Text('¿No te funciona? Usar clave de Web API'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Versión ${AppConstants.appVersion}',
            style: TextStyle(
              fontSize: 11,
              color: WatapColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _skip(BuildContext context) async {
    final AppController controller = AppScope.of(context);
    await controller.skipFamilySetup();
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.description,
    required this.done,
    required this.doneText,
    required this.pendingText,
    required this.actionLabel,
    required this.onAction,
  });

  final int index;
  final String title;
  final String description;
  final bool done;
  final String doneText;
  final String pendingText;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final Color accent = done ? WatapColors.success : WatapColors.warning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.55)),
                  ),
                  child: done
                      ? Icon(Icons.check, size: 16, color: accent)
                      : Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: WatapColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: WatapColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        done ? doneText : pendingText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: done
                  ? OutlinedButton(onPressed: onAction, child: Text(actionLabel))
                  : FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
