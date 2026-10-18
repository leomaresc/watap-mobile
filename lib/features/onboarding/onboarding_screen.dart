/// Asistente de configuración inicial.
///
/// Dos pasos:
/// 1. Clave de Steam Web API (indispensable para leer la actividad).
/// 2. Conexión con Steam mediante un WebView de la página oficial, para poder
///    leer el grupo familiar e importar los integrantes automáticamente.
///
/// El paso 2 puede omitirse explícitamente para no bloquear la aplicación si la
/// página de Steam no carga; puede conectarse más tarde desde Integrantes.
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
    final bool hasKey = controller.hasApiKey;
    final bool connected = controller.hasFamilyToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración inicial'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const Text(
            'Dos pasos y WATAP queda listo',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: WatapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La clave consulta la actividad de cada integrante. La conexión con '
            'Steam sirve para leer tu grupo familiar y añadirlos solos, sin '
            'que tengas que copiar nada a mano.',
            style: TextStyle(
              fontSize: 13,
              color: WatapColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          _StepCard(
            index: 1,
            title: 'Clave de Steam Web API',
            description:
                'Consulta los juegos recientes de cada integrante. Es gratuita '
                'y se solicita en la página oficial de Steam.',
            done: hasKey,
            doneText: 'Clave guardada en el almacenamiento seguro.',
            pendingText: 'Falta configurar la clave.',
            actionLabel: hasKey ? 'Cambiar la clave' : 'Configurar la clave',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const ApiKeyScreen(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _StepCard(
            index: 2,
            title: 'Conectar con Steam (grupo familiar)',
            description:
                'Se abre la página oficial de inicio de sesión de Steam dentro '
                'de la app. Tu contraseña va directamente a Steam: WATAP no la '
                've ni la guarda. Después se leen tus integrantes solos.',
            done: connected,
            doneText: connected
                ? 'Conectado. El grupo familiar se puede sincronizar.'
                : 'Sin conectar: tendrás que añadir integrantes a mano.',
            pendingText: 'Pendiente de conexión.',
            actionLabel: connected ? 'Volver a conectar' : 'Conectar con Steam',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const SteamConnectScreen(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (hasKey && connected)
            const InlineNotice(
              message: 'Todo listo. Tus integrantes del grupo familiar se han '
                  'importado automáticamente.',
              icon: Icons.check_circle_outline,
              color: WatapColors.success,
            )
          else if (hasKey)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const InlineNotice(
                  message: 'La clave se guarda solo en el almacén seguro del '
                      'dispositivo. Nunca se escribe en la base de datos ni en '
                      'archivos.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _skip(context),
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('Omitir el paso 2 por ahora'),
                ),
              ],
            )
          else
            const InlineNotice(
              message: 'Empieza por la clave de Steam Web API.',
              icon: Icons.key_outlined,
              color: WatapColors.warning,
            ),
          const SizedBox(height: 16),
          Text(
            'Versión ${AppConstants.appVersion}',
            style: const TextStyle(
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
