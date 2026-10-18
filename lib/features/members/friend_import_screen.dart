/// Importación opcional de amigos desde la API documentada de Steam.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';

/// Pantalla de selección de amigos para importar.
///
/// La lista de amigos es privada por defecto en Steam: si no es accesible, se
/// explica la causa y se invita a añadir los perfiles manualmente. No se
/// promete que funcione para todas las cuentas.
class FriendImportScreen extends StatefulWidget {
  const FriendImportScreen({super.key});

  @override
  State<FriendImportScreen> createState() => _FriendImportScreenState();
}

class _FriendImportScreenState extends State<FriendImportScreen> {
  bool _loading = true;
  String? _message;
  bool _isError = false;
  List<SteamPlayerSummary> _friends = const <SteamPlayerSummary>[];
  final Set<String> _selected = <String>{};
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
      _isError = false;
      _selected.clear();
    });
    final AppController controller = AppScope.of(context);
    final FriendImportResult result = await controller.loadFriends();
    if (!mounted) return;
    final Set<String> existing =
        controller.realProfiles.map((Profile p) => p.steamId64).toSet();
    setState(() {
      _loading = false;
      _friends = result.friends
          .where((SteamPlayerSummary f) => !existing.contains(f.steamId64))
          .toList(growable: false);
      _message = _friends.isEmpty && !result.isError
          ? 'No hay amigos nuevos que añadir. Es posible que ya estén todos en '
              'tu lista de integrantes.'
          : result.messageEs;
      _isError = result.isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar amigos'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Volver a consultar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: _friends.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: (_selected.isEmpty || _adding) ? null : _addSelected,
                  icon: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all),
                  label: Text(
                    'Añadir ${_selected.length} '
                    'seleccionado${_selected.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingState(message: 'Consultando tu lista de amigos…');
    }

    if (_isError) {
      return ErrorState(
        title: 'No se pudo obtener la lista de amigos',
        message: _message ??
            'Steam no ha entregado la lista. Puedes añadir los integrantes '
            'manualmente desde la pantalla Integrantes.',
        onRetry: _load,
      );
    }

    if (_friends.isEmpty) {
      return EmptyState(
        title: 'Sin amigos que importar',
        message: _message ??
            'Steam no ha devuelto amigos nuevos para añadir.',
        icon: Icons.group_off_outlined,
        actionLabel: 'Volver a intentarlo',
        onAction: _load,
      );
    }

    final bool allSelected = _selected.length == _friends.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: <Widget>[
        if (_message != null) ...<Widget>[
          InlineNotice(message: _message!),
          const SizedBox(height: 10),
        ],
        const InlineNotice(
          message: 'Se muestran solo los amigos que aún no están en tu lista. '
              'La importación requiere que tu lista de amigos sea accesible con '
              'la clave configurada.',
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (allSelected) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(_friends.map((SteamPlayerSummary f) => f.steamId64));
                  }
                });
              },
              icon: Icon(
                allSelected ? Icons.check_box_outline_blank : Icons.check_box,
                size: 18,
              ),
              label: Text(allSelected ? 'Quitar todos' : 'Seleccionar todos'),
            ),
          ],
        ),
        for (final SteamPlayerSummary friend in _friends)
          Card(
            child: CheckboxListTile(
              value: _selected.contains(friend.steamId64),
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    _selected.add(friend.steamId64);
                  } else {
                    _selected.remove(friend.steamId64);
                  }
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                friend.personaName ?? 'Perfil ${friend.steamId64}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WatapColors.textPrimary,
                ),
              ),
              subtitle: Text(
                friend.steamId64,
                style: const TextStyle(
                  fontSize: 11,
                  color: WatapColors.textSecondary,
                ),
              ),
              secondary: AvatarWidget(
                displayName: friend.personaName ?? friend.steamId64,
                avatarUrl: friend.avatarUrl,
                size: 38,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _addSelected() async {
    final AppController controller = AppScope.of(context);
    final List<SteamPlayerSummary> selected = _friends
        .where((SteamPlayerSummary f) => _selected.contains(f.steamId64))
        .toList(growable: false);

    setState(() => _adding = true);
    final OperationResult result = await controller.addImportedProfiles(selected);
    if (!mounted) return;
    setState(() => _adding = false);
    showMessage(context, result.messageEs, isError: !result.success);
    Navigator.of(context).pop();
  }
}
