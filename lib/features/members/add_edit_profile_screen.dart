/// Formulario para editar un integrante o añadir un perfil de rescate.
///
/// El alta normal de integrantes la hace el grupo familiar de Steam de forma
/// automática; el modo "añadir" existe solo como excepción.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/validators.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';

/// Pantalla de edición y de alta manual de excepción.
class AddEditProfileScreen extends StatefulWidget {
  const AddEditProfileScreen({super.key, this.profile});

  /// Si es `null`, la pantalla añade un perfil de rescate.
  final Profile? profile;

  @override
  State<AddEditProfileScreen> createState() => _AddEditProfileScreenState();
}

class _AddEditProfileScreenState extends State<AddEditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _inputController;
  late final TextEditingController _aliasController;

  bool _saving = false;
  String? _errorMessage;

  /// Aviso sobre el formato de la entrada, recalculado mientras se escribe.
  String? _formatHint;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _aliasController = TextEditingController(text: widget.profile?.alias ?? '');
    if (!_isEditing) _inputController.addListener(_updateFormatHint);
  }

  /// Avisa (sin bloquear) cuando un SteamID64 no parece de una cuenta personal.
  void _updateFormatHint() {
    final ProfileInputResult result = parseProfileInput(_inputController.text);
    String? hint;
    if (result.isValid && result.input!.isSteamId64) {
      if (!looksLikeIndividualSteamId64(result.input!.value)) {
        hint = 'Ese identificador no empieza por 7656119, el prefijo habitual de '
            'las cuentas personales de Steam. Puede ser un identificador de '
            'grupo o de otro tipo.';
      }
    }
    if (hint != _formatHint) setState(() => _formatHint = hint);
  }

  @override
  void dispose() {
    if (!_isEditing) _inputController.removeListener(_updateFormatHint);
    _inputController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar integrante' : 'Añadir perfil a mano'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            if (_isEditing) ...<Widget>[
              Row(
                children: <Widget>[
                  AvatarWidget(
                    displayName: widget.profile!.displayName,
                    avatarUrl: widget.profile!.avatarUrl,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.profile!.personaName ?? 'Nombre no disponible',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: WatapColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.profile!.steamId64,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WatapColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Perfil supervisado',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: WatapColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _aliasController,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Alias local (opcional)',
                  helperText: 'Sirve para distinguir a las personas en tu lista. '
                      'No se envía a Steam ni lo ve nadie más.',
                  counterText: '',
                ),
                validator: validateAlias,
              ),
              const SizedBox(height: 12),
            ] else ...<Widget>[
              const InlineNotice(
                message: 'Añade un perfil de Steam por SteamID64, URL o nombre '
                    'personalizado.',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _inputController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Perfil de Steam',
                  hintText: '7656119…  ·  https://steamcommunity.com/id/…',
                  prefixIcon: Icon(Icons.person_search_outlined),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Introduce un SteamID64, una URL o un nombre '
                        'personalizado.';
                  }
                  final ProfileInputResult result = parseProfileInput(value);
                  if (!result.isValid) return result.errorEs;
                  return null;
                },
                onFieldSubmitted: (_) => _submit(controller),
              ),
              if (_formatHint != null) ...<Widget>[
                const SizedBox(height: 10),
                InlineNotice(
                  message: _formatHint!,
                  icon: Icons.warning_amber_outlined,
                  color: WatapColors.warning,
                ),
              ],
              const SizedBox(height: 10),
              if (!controller.hasApiKey)
                const InlineNotice(
                  message: 'Sin clave de Web API solo se puede guardar el perfil: '
                      'el nombre y la actividad se obtendrán cuando la '
                      'configures en Ajustes.',
                  icon: Icons.key_off_outlined,
                  color: WatapColors.warning,
                ),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 14),
              InlineNotice(
                message: _errorMessage!,
                icon: Icons.error_outline,
                color: WatapColors.activityHigh,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : () => _submit(controller),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isEditing ? Icons.save_outlined : Icons.add),
              label: Text(_isEditing ? 'Guardar cambios' : 'Añadir perfil'),
            ),
            if (_saving) ...<Widget>[
              const SizedBox(height: 16),
              const LoadingState(
                compact: true,
                message: 'Consultando a Steam…',
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Los perfiles repetidos se rechazan por SteamID64, sea cual sea '
              'el alias. La existencia de una cuenta se comprueba con la API: '
              'que una cadena tenga 17 dígitos no garantiza que la cuenta '
              'exista.',
              style: TextStyle(
                fontSize: 11.5,
                color: WatapColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (_isEditing) ...<Widget>[
              const Divider(height: 40),
              OutlinedButton.icon(
                onPressed: () => _delete(controller),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WatapColors.activityHigh,
                  side: const BorderSide(color: WatapColors.activityHigh),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar integrante'),
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => openExternalUrl(
                  context,
                  SteamApiUrls.communityProfile(
                    widget.profile?.steamId64 ?? '76561197960435530',
                  ),
                  action: 'abrir Steam',
                ),
                icon: const Icon(Icons.help_outline, size: 16),
                label: const Text('¿Cómo encuentro mi SteamID64?'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(AppController controller) async {
    setState(() {
      _errorMessage = null;
    });

    if (_isEditing) {
      _saving = true;
      setState(() {});
      final OperationResult result = await controller.updateProfile(
        steamId64: widget.profile!.steamId64,
        alias: _aliasController.text,
      );
      _saving = false;
      if (!mounted) return;
      setState(() {});
      if (result.success) {
        showMessage(context, result.messageEs);
        Navigator.of(context).pop();
      } else {
        setState(() => _errorMessage = result.messageEs);
      }
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    _saving = true;
    setState(() {});
    final OperationResult result =
        await controller.addProfile(_inputController.text);
    _saving = false;
    if (!mounted) return;
    setState(() {});
    if (result.success) {
      showMessage(context, result.messageEs);
      Navigator.of(context).pop();
      if (result.steamId64 != null) {
        // Se consulta la actividad inmediatamente para que la pantalla Recientes
        // sea útil sin pasos extra.
        unawaited(controller.refreshProfile(result.steamId64!));
      }
    } else {
      setState(() => _errorMessage = result.messageEs);
    }
  }

  Future<void> _delete(AppController controller) async {
    final bool confirmed = await confirmAction(
      context,
      title: 'Eliminar integrante',
      message: 'Se eliminará ${widget.profile!.displayName} y su actividad '
          'guardada en la caché local.',
    );
    if (!confirmed || !mounted) return;
    final OperationResult result =
        await controller.deleteProfile(widget.profile!.steamId64);
    if (!mounted) return;
    showMessage(context, result.messageEs, isError: !result.success);
    Navigator.of(context).pop();
  }
}
