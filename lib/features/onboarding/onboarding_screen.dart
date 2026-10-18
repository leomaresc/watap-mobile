/// Asistente de configuración inicial.
///
/// WATAP necesita una clave de Steam Web API para funcionar. Mientras no haya
/// una clave configurada, se muestra esta pantalla en lugar del panel principal.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';
import '../settings/api_key_screen.dart';

/// Pantalla de configuración inicial (solo clave de API).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
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
            'WATAP necesita una clave de Steam Web API',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: WatapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La clave se usa para consultar los juegos recientes de los '
            'perfiles que añadas. Es gratuita y se solicita en la página '
            'oficial de Steam con tu propia cuenta.',
            style: TextStyle(
              fontSize: 13,
              color: WatapColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (hasKey ? WatapColors.success : WatapColors.warning)
                              .withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (hasKey
                                    ? WatapColors.success
                                    : WatapColors.warning)
                                .withValues(alpha: 0.55),
                          ),
                        ),
                        child: hasKey
                            ? const Icon(Icons.check,
                                size: 16, color: WatapColors.success)
                            : const Text(
                                '1',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: WatapColors.warning,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Clave de Steam Web API',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: WatapColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasKey
                                  ? 'Clave configurada en el almacenamiento seguro.'
                                  : 'Falta configurar la clave.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: hasKey
                                    ? WatapColors.success
                                    : WatapColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '1. Inicia sesión en Steam con un navegador.\n'
                    '2. Entra en la página oficial de registro de claves.\n'
                    '3. Rellena el dominio con un nombre que controles (por '
                    'ejemplo, "watap.local").\n'
                    '4. Copia la clave y pégala en la pantalla de configuración.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: WatapColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) => const ApiKeyScreen(),
                      ),
                    ),
                    icon: hasKey
                        ? const Icon(Icons.edit_outlined, size: 18)
                        : const Icon(Icons.open_in_new, size: 18),
                    label: Text(hasKey ? 'Cambiar la clave' : 'Configurar la clave'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (hasKey)
            const InlineNotice(
              message: 'Todo listo. Ya puedes importar integrantes y ver su '
                  'actividad reciente.',
              icon: Icons.check_circle_outline,
              color: WatapColors.success,
            )
          else
            const InlineNotice(
              message: 'La clave se guarda solo en el almacenamiento seguro '
                  'del dispositivo (Keystore en Android, Keychain en iOS). '
                  'Nunca se escribe en la base de datos ni en archivos.',
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
}