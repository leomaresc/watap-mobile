/// Asistente de configuración inicial.
///
/// WATAP no funciona sin credenciales: se muestra esta pantalla mientras falte
/// la clave de Steam Web API o la sesión de Steam. No hay modo de demostración
/// ni datos ficticios.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';
import '../settings/api_key_screen.dart';
import 'steam_login_screen.dart';
/// Pantalla que guía al usuario en la configuración obligatoria.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
    final bool hasKey = controller.hasApiKey;
    final bool hasSession = controller.hasSteamSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración inicial'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const Text(
            'Para funcionar, WATAP necesita dos credenciales',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: WatapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La aplicación no trae datos de ejemplo: todo lo que muestra viene '
            'de Steam. Los integrantes se cargan solos desde tu grupo familiar.',
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
                'Con la clave se consultan los juegos recientes de cada '
                'integrante. Es gratuita y se solicita en la página oficial de '
                'Steam con tu propia cuenta.',
            done: hasKey,
            doneText: 'Clave configurada en el almacenamiento seguro.',
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
            title: 'Cuenta de Steam (grupo familiar)',
            description:
                'Steam solo entrega la lista de integrantes del grupo familiar a '
                'una sesión iniciada. Inicia sesión una vez: WATAP guardará los '
                'tokens en el almacenamiento seguro y no volverá a pedirte la '
                'contraseña.',
            done: hasSession,
            doneText: controller.steamAccountName == null
                ? 'Sesión de Steam iniciada.'
                : 'Conectado como ${controller.steamAccountName}.',
            pendingText: 'Sin sesión de Steam.',
            actionLabel: hasSession
                ? 'Cerrar sesión de Steam'
                : 'Iniciar sesión en Steam',
            onAction: hasSession
                ? () async {
                    final OperationResult result = await controller.logoutSteam();
                    if (!context.mounted) return;
                    showMessage(context, result.messageEs, isError: !result.success);
                  }
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) => const SteamLoginScreen(),
                      ),
                    ),
          ),
          const SizedBox(height: 20),
          if (hasKey && hasSession)
            const InlineNotice(
              message: 'Todo listo. WATAP está cargando los integrantes de tu '
                  'grupo familiar…',
              icon: Icons.check_circle_outline,
              color: WatapColors.success,
            )
          else
            const InlineNotice(
              message: 'Ninguna de las dos credenciales sale del dispositivo '
                  'salvo para hablar directamente con Steam por HTTPS.',
            ),
          const SizedBox(height: 16),
          const Text(
            'Sobre la contraseña de Steam: se cifra en el teléfono con la clave '
            'pública de Steam y se envía solo a Steam. WATAP no la guarda, no la '
            'registra y no puede leerla después.',
            style: TextStyle(
              fontSize: 11.5,
              color: WatapColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
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
