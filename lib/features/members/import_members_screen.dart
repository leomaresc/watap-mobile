/// Pantalla de importación de integrantes por lista pegada.
///
/// El usuario pega una lista de SteamID64, URLs de perfil de Steam o nombres
/// personalizados. WATAP los resuelve con la API y añade los perfiles
/// encontrados.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';

/// Pantalla de importación masiva de integrantes.
class ImportMembersScreen extends StatefulWidget {
  const ImportMembersScreen({super.key});

  @override
  State<ImportMembersScreen> createState() => _ImportMembersScreenState();
}

class _ImportMembersScreenState extends State<ImportMembersScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _importing = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Importar integrantes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const InlineNotice(
            message: 'Pega una lista de perfiles de Steam, uno por línea. '
                'Cada entrada puede ser un SteamID64 (17 dígitos), una URL de '
                'perfil (steamcommunity.com/profiles/… o /id/…) o un nombre '
                'personalizado. WATAP los resuelve con la API y añade los '
                'perfiles encontrados.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 12,
            minLines: 6,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Lista de perfiles',
              hintText: '76561198000000000\n'
                  'https://steamcommunity.com/id/nombre\n'
                  'nombrePersonalizado',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 14),
            InlineNotice(
              message: _message!,
              icon: _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
              color: _messageIsError ? WatapColors.activityHigh : WatapColors.success,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _importing ? null : () => _import(controller),
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(_importing ? 'Importando…' : 'Importar integrantes'),
          ),
          if (_importing) ...<Widget>[
            const SizedBox(height: 16),
            const LoadingState(
              compact: true,
              message: 'Consultando a Steam…',
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Los perfiles repetidos se omiten. Un nombre personalizado que no '
            'exista se descarta sin abortar el resto de la importación. La '
            'existencia de una cuenta se comprueba con la API de Steam: tener '
            '17 dígitos no garantiza que la cuenta exista.',
            style: TextStyle(
              fontSize: 11.5,
              color: WatapColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import(AppController controller) async {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _message = 'Pega al menos un perfil de Steam.';
        _messageIsError = true;
      });
      return;
    }

    // Se separan las líneas y se descartan las vacías.
    final List<String> entries = text
        .split(RegExp(r'[\r\n,]+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);

    if (entries.isEmpty) {
      setState(() {
        _message = 'No se encontraron entradas en el texto pegado.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _importing = true;
      _message = null;
    });

    final ImportResult result = await controller.importMembers(entries);

    if (!mounted) return;
    setState(() {
      _importing = false;
      _message = result.messageEs;
      _messageIsError = result.isError;
    });

    if (result.added > 0) {
      // Se consulta la actividad de los nuevos perfiles en segundo plano.
      for (final Profile profile in controller.profiles) {
        unawaited(controller.refreshProfile(profile.steamId64));
      }
    }
  }
}