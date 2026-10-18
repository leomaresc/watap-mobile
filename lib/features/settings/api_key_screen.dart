/// Pantalla de configuración de la clave de Steam Web API.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/validators.dart';
import '../../data/steam/steam_api_client.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';

/// Configuración, verificación y eliminación de la clave de API.
class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key});

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _working = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    // Se limpia el contenido del campo en memoria al salir de la pantalla.
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Clave de Steam Web API')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const InlineNotice(
            message: 'WATAP usa tu propia clave personal de Steam Web API. La '
                'clave se guarda únicamente en el almacenamiento seguro del '
                'dispositivo (Keystore en Android, Keychain en iOS) y nunca se '
                'escribe en la base de datos, en archivos de configuración ni en '
                'los registros de la aplicación.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '¿Cómo consigo la clave?',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: WatapColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Inicia sesión en tu cuenta de Steam con un navegador.\n'
                    '2. Entra en la página oficial de registro de claves.\n'
                    '3. Rellena el dominio del formulario con un nombre de '
                    'dominio que controles (por ejemplo, "watap.local" o tu '
                    'propio dominio) y acepta las condiciones.\n'
                    '4. Copia la clave que Steam te muestra y pégala aquí.',
                    style: TextStyle(
                      fontSize: 13,
                      color: WatapColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => openExternalUrl(
                      context,
                      SteamApiUrls.apiKeyRegistration(),
                      action: 'abrir la página de registro de Steam',
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Abrir la página de registro de Steam'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Steam solicita un dominio durante el registro. Para una '
                    'aplicación móvil personal basta con un nombre de dominio '
                    'propio o un valor descriptivo; no se usa para publicar nada.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: WatapColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            controller.hasApiKey
                ? 'Ya hay una clave guardada. Puedes sustituirla introduciendo '
                    'otra, o eliminarla para dejar de usarla.'
                : 'Introduce tu clave para activar las consultas reales.',
            style: const TextStyle(
              fontSize: 13,
              color: WatapColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _controller,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Clave de Steam Web API',
                helperText: 'No se mostrará de nuevo después de guardarla.',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar la clave' : 'Ocultar la clave',
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Introduce la clave que te ha dado Steam.';
                }
                return validateApiKeyFormat(value);
              },
            ),
          ),
          if (_statusMessage != null) ...<Widget>[
            const SizedBox(height: 14),
            InlineNotice(
              message: _statusMessage!,
              icon: _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
              color: _statusIsError ? WatapColors.activityHigh : WatapColors.success,
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _working ? null : () => _save(controller),
            icon: _working
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar la clave'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _working ? null : () => _verify(controller),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: const Text('Guardar y verificar'),
          ),
          if (controller.hasApiKey) ...<Widget>[
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _working ? null : () => _delete(controller),
              style: OutlinedButton.styleFrom(
                foregroundColor: WatapColors.activityHigh,
                side: const BorderSide(color: WatapColors.activityHigh),
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar la clave del dispositivo'),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'La comprobación de la clave es real: se consulta el endpoint '
            'documentado ISteamUser/GetPlayerSummaries. Si Steam responde con un '
            'error 401 o 403 en ese endpoint, la clave se considera rechazada. '
            'Si el error es de red o de tiempo de espera, WATAP no puede '
            'determinar el estado de la clave y lo indica como tal.',
            style: TextStyle(
              fontSize: 11.5,
              color: WatapColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Transparencia: el almacenamiento seguro protege la clave en reposo. '
            'Ninguna aplicación cliente puede garantizar protección absoluta '
            'frente a un dispositivo comprometido, con acceso root o con '
            'ejecución instrumentada.',
            style: TextStyle(
              fontSize: 11.5,
              color: WatapColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Almacén seguro: ${AppConstants.apiKeyStorageKey}',
            style: TextStyle(
              fontSize: 11,
              color: WatapColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(AppController controller, {bool verifyAfter = false}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _working = true;
      _statusMessage = null;
    });

    final OperationResult result = await controller.saveApiKey(_controller.text);
    // El campo se vacía en cuanto la clave queda guardada: no debe permanecer en
    // pantalla ni en memoria del formulario.
    _controller.clear();

    if (!verifyAfter || !result.success) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _statusMessage = result.messageEs;
        _statusIsError = !result.success;
      });
      return;
    }

    final ApiKeyCheckResult check = await controller.verifyApiKey();
    if (!mounted) return;
    setState(() {
      _working = false;
      _statusMessage = '${result.messageEs}\n\n${check.messageEs}';
      _statusIsError = check.keyAccepted == false;
    });
  }

  Future<void> _verify(AppController controller) async {
    if (_controller.text.trim().isEmpty) {
      if (!controller.hasApiKey) {
        setState(() {
          _statusMessage = 'Escribe primero una clave o guarda una antes de '
              'verificarla.';
          _statusIsError = true;
        });
        return;
      }
    } else {
      await _save(controller, verifyAfter: true);
      return;
    }

    setState(() {
      _working = true;
      _statusMessage = null;
    });
    final ApiKeyCheckResult check = await controller.verifyApiKey();
    if (!mounted) return;
    setState(() {
      _working = false;
      _statusMessage = check.messageEs +
          (check.technicalDetail == null ? '' : ' (${check.technicalDetail})');
      _statusIsError = check.keyAccepted == false;
    });
  }

  Future<void> _delete(AppController controller) async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Eliminar la clave',
      message: 'Se borrará la clave del almacenamiento seguro del dispositivo. '
          'Podrás seguir viendo los datos guardados en la caché local.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    final OperationResult result = await controller.deleteApiKey();
    if (!mounted) return;
    setState(() {
      _working = false;
      _statusMessage = result.messageEs;
      _statusIsError = false;
    });
  }
}
