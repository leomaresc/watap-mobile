/// Pantalla "Ajustes".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../core/validators.dart';
import '../../data/steam/steam_api_client.dart';
import '../../services/family_group_sync.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_helpers.dart';
import '../about/about_screen.dart';
import '../onboarding/steam_login_screen.dart';
import 'api_key_screen.dart';
import 'privacy_screen.dart';

/// Pantalla de configuración de WATAP.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
    final Preferences prefs = controller.preferences;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: <Widget>[
        SectionCard(
          title: 'CUENTA DE STEAM',
          subtitle: 'Con la sesión iniciada, WATAP lee tu grupo familiar y carga '
              'los integrantes automáticamente',
          children: <Widget>[
            ListTile(
              leading: Icon(
                controller.hasSteamSession ? Icons.link : Icons.link_off,
                color: controller.hasSteamSession
                    ? WatapColors.success
                    : WatapColors.warning,
              ),
              title: Text(
                controller.hasSteamSession
                    ? (controller.steamAccountName == null
                        ? 'Sesión de Steam activa'
                        : 'Conectado como ${controller.steamAccountName}')
                    : 'Sin sesión de Steam',
              ),
              subtitle: Text(
                controller.hasSteamSession
                    ? 'Los tokens se guardan cifrados en el dispositivo. '
                        'WATAP no conserva tu contraseña.'
                    : 'Inicia sesión una vez para que WATAP pueda leer el grupo '
                        'familiar.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const SteamLoginScreen(),
                ),
              ),
            ),
            if (controller.hasSteamSession) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sincronizar el grupo familiar'),
                subtitle: Text(
                  'Ahora mismo hay ${controller.familyMembers.length} integrantes '
                  'del grupo familiar',
                ),
                onTap: () async {
                  final FamilySyncOutcome outcome =
                      await controller.syncFamilyGroup();
                  if (!context.mounted) return;
                  showMessage(
                    context,
                    outcome.messageEs,
                    isError: !outcome.success,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión de Steam'),
                subtitle: const Text(
                  'Elimina los tokens del dispositivo. Los integrantes guardados '
                  'se conservan.',
                ),
                onTap: () async {
                  final bool confirmed = await confirmAction(
                    context,
                    title: 'Cerrar sesión de Steam',
                    message: 'Se eliminarán del dispositivo los tokens de la '
                        'sesión. Tendrás que iniciar sesión otra vez para volver '
                        'a leer el grupo familiar.',
                  );
                  if (!confirmed || !context.mounted) return;
                  final OperationResult result = await controller.logoutSteam();
                  if (!context.mounted) return;
                  showMessage(context, result.messageEs, isError: !result.success);
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'STEAM WEB API',
          subtitle: 'La clave se guarda solo en el almacenamiento seguro del '
              'dispositivo',
          children: <Widget>[
            ListTile(
              leading: Icon(
                controller.hasApiKey ? Icons.key : Icons.key_off_outlined,
                color: controller.hasApiKey
                    ? WatapColors.success
                    : WatapColors.warning,
              ),
              title: Text(
                controller.hasApiKey ? 'Clave configurada' : 'Sin clave configurada',
              ),
              subtitle: Text(
                controller.hasApiKey
                    ? 'Guardada en el almacén seguro. WATAP no muestra su '
                        'contenido ni la incluye en registros.'
                    : 'Sin clave no se puede consultar la actividad de los '
                        'integrantes.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const ApiKeyScreen(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Verificar la clave'),
              subtitle: const Text(
                'Realiza una consulta real a Steam para comprobar la '
                'configuración',
              ),
              onTap: controller.hasApiKey
                  ? () async {
                      final ApiKeyCheckResult result = await controller.verifyApiKey();
                      if (!context.mounted) return;
                      showMessage(
                        context,
                        result.messageEs,
                        isError: result.keyAccepted == false,
                      );
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'ACTUALIZACIÓN',
          children: <Widget>[
            SwitchListTile(
              secondary: const Icon(Icons.sync),
              title: const Text('Actualizar al abrir'),
              subtitle: const Text(
                'Intenta actualizar al abrir la aplicación o al volver al primer '
                'plano. No es una actualización garantizada: depende de la red y '
                'de los límites de Steam.',
              ),
              value: prefs.refreshOnOpen,
              onChanged: (bool value) => controller.savePreferences(
                prefs.copyWith(refreshOnOpen: value),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.restore),
              title: const Text('Abrir en la última sección'),
              subtitle: const Text(
                'Restaura Recientes, General, Familia o Ajustes al iniciar',
              ),
              value: prefs.openLastViewedSection,
              onChanged: (bool value) => controller.savePreferences(
                prefs.copyWith(openLastViewedSection: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'VISUALIZACIÓN',
          children: <Widget>[
            SwitchListTile(
              secondary: const Icon(Icons.image_outlined),
              title: const Text('Mostrar portadas'),
              subtitle: const Text(
                'Desactívalo para ahorrar datos móviles. La información textual '
                'se mantiene siempre.',
              ),
              value: prefs.showCovers,
              onChanged: (bool value) => controller.savePreferences(
                prefs.copyWith(showCovers: value),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.filter_alt_outlined),
              title: const Text('Ocultar juegos con poca actividad'),
              subtitle: Text(
                'Oculta los juegos con menos de '
                '${prefs.lowActivityFilterMinutes} minutos recientes',
              ),
              value: prefs.hideLowActivity,
              onChanged: (bool value) => controller.savePreferences(
                prefs.copyWith(hideLowActivity: value),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Umbrales de actividad'),
              subtitle: Text(
                'Baja: menos de ${prefs.moderateActivityMinutes} min · '
                'Moderada: ${prefs.moderateActivityMinutes}–'
                '${prefs.highActivityMinutes} min · '
                'Alta: ${prefs.highActivityMinutes} min o más',
              ),
              onTap: () => _editThresholds(context, controller),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'ALMACENAMIENTO Y CACHÉ',
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Caché de imágenes'),
              subtitle: Text(
                'Ocupa aproximadamente ${controller.imageCacheSizeLabel}. '
                'Se reutiliza entre sesiones.',
              ),
              onTap: controller.refreshImageCacheSize,
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Borrar caché de imágenes'),
              subtitle: const Text('Libera el espacio de las portadas y avatares'),
              onTap: () async {
                final bool confirmed = await confirmAction(
                  context,
                  title: 'Borrar caché de imágenes',
                  message: 'Se eliminarán las portadas y los avatares '
                      'descargados. Volverán a descargarse cuando haga falta.',
                  confirmLabel: 'Borrar',
                );
                if (!confirmed || !context.mounted) return;
                final OperationResult result = await controller.clearImageCache();
                if (!context.mounted) return;
                showMessage(context, result.messageEs, isError: !result.success);
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Borrar caché de actividad'),
              subtitle: Text(
                'Elimina los juegos y estados guardados de '
                '${controller.profiles.length} integrante'
                '${controller.profiles.length == 1 ? '' : 's'}. '
                'La lista de perfiles se conserva.',
              ),
              onTap: () async {
                final bool confirmed = await confirmAction(
                  context,
                  title: 'Borrar caché de actividad',
                  message: 'Se borrarán los datos de actividad guardados. Los '
                      'integrantes se mantendrán en tu lista.',
                  confirmLabel: 'Borrar',
                );
                if (!confirmed || !context.mounted) return;
                final OperationResult result = await controller.clearActivityCache();
                if (!context.mounted) return;
                showMessage(context, result.messageEs, isError: !result.success);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'PRIVACIDAD E INFORMACIÓN',
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacidad y almacenamiento local'),
              subtitle: const Text(
                'Qué guarda WATAP, dónde y qué nunca se envía',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const PrivacyScreen(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Acerca de WATAP'),
              subtitle: const Text('Versión ${AppConstants.appVersion}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => const AboutScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Diálogo de edición de los tres umbrales de actividad.
  Future<void> _editThresholds(
    BuildContext context,
    AppController controller,
  ) async {
    final Preferences prefs = controller.preferences;
    final TextEditingController lowController = TextEditingController(
      text: '${prefs.lowActivityFilterMinutes}',
    );
    final TextEditingController moderateController = TextEditingController(
      text: '${prefs.moderateActivityMinutes}',
    );
    final TextEditingController highController = TextEditingController(
      text: '${prefs.highActivityMinutes}',
    );
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Umbrales de actividad'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Se usan para clasificar la actividad y para el filtro de '
                  '"poca actividad". El umbral moderado debe ser menor que el '
                  'alto.',
                  style: TextStyle(fontSize: 12.5, color: WatapColors.textSecondary),
                ),
                const SizedBox(height: 14),
                _numberField(
                  lowController,
                  label: 'Filtro de poca actividad (minutos)',
                ),
                const SizedBox(height: 10),
                _numberField(
                  moderateController,
                  label: 'Actividad moderada desde (minutos)',
                ),
                const SizedBox(height: 10),
                _numberField(
                  highController,
                  label: 'Actividad alta desde (minutos)',
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final int moderate = int.parse(moderateController.text.trim());
              final int high = int.parse(highController.text.trim());
              final String? error = validateActivityThresholds(moderate, high);
              if (error != null) {
                showMessage(ctx, error, isError: true);
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    await controller.savePreferences(
      prefs.copyWith(
        lowActivityFilterMinutes: int.parse(lowController.text.trim()),
        moderateActivityMinutes: int.parse(moderateController.text.trim()),
        highActivityMinutes: int.parse(highController.text.trim()),
      ),
    );
    if (context.mounted) {
      showMessage(context, 'Umbrales de actividad actualizados.');
    }
  }

  Widget _numberField(TextEditingController controller, {required String label}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
      validator: (String? value) {
        final int? parsed = int.tryParse((value ?? '').trim());
        return validateThreshold(parsed, label: 'El umbral');
      },
    );
  }
}
