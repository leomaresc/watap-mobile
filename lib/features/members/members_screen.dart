/// Pantalla "Integrantes": lista de perfiles supervisados.
///
/// Los perfiles se importan de una vez pegando una lista de SteamID64, URLs o
/// nombres personalizados de Steam. La app resuelve cada entrada con la API.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/ui_helpers.dart';
import 'add_edit_profile_screen.dart';
import 'import_members_screen.dart';

/// Pantalla de integrantes supervisados.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    if (!controller.initialized) {
      return const LoadingState(message: 'Preparando los datos locales…');
    }
    if (controller.initializationError != null) {
      return ErrorState(
        title: 'No se pudo preparar los datos locales',
        message: controller.initializationError!,
        onRetry: controller.retryInitialize,
      );
    }

    final List<Profile> profiles = controller.profiles;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openImport(context),
        backgroundColor: WatapColors.accent,
        foregroundColor: const Color(0xFF08202C),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Importar'),
      ),
      body: profiles.isEmpty
          ? EmptyState(
              title: 'Todavía no hay integrantes',
              message: 'Pega una lista de SteamID64, URLs de perfil o nombres '
                  'personalizados de Steam y WATAP los importará de una vez.',
              icon: Icons.group_add_outlined,
              actionLabel: 'Importar integrantes',
              onAction: () => _openImport(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: <Widget>[
                const InlineNotice(
                  message: 'Esta lista es tu selección personal. WATAP no '
                      'verifica que los integrantes pertenezcan a un mismo '
                      'grupo o familia de Steam.',
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'ACCIONES',
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('Importar integrantes'),
                      subtitle: const Text(
                        'Pega una lista de SteamID64, URLs o nombres '
                        'personalizados',
                      ),
                      onTap: () => _openImport(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1),
                      title: const Text('Añadir un solo perfil'),
                      subtitle: const Text(
                        'Por SteamID64, URL o nombre personalizado',
                      ),
                      onTap: () => _openAdd(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'INTEGRANTES (${profiles.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WatapColors.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                for (final Profile profile in profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MemberTile(controller: controller, profile: profile),
                  ),
              ],
            ),
    );
  }

  void _openImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const ImportMembersScreen(),
      ),
    );
  }

  void _openAdd(BuildContext context, {Profile? profile}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => AddEditProfileScreen(profile: profile),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.controller, required this.profile});

  final AppController controller;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final ProfileActivity? activity = controller.activityFor(profile.steamId64);
    final bool refreshing = controller.isRefreshing(profile.steamId64);
    final FetchStatus status = activity?.status ?? FetchStatus.notFetched;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AvatarWidget(
              displayName: profile.displayName,
              avatarUrl: profile.avatarUrl,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          profile.displayName,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: WatapColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.steamId64,
                    style: const TextStyle(
                      fontSize: 11,
                      color: WatapColors.textSecondary,
                    ),
                  ),
                  if (profile.alias != null && profile.alias!.trim().isNotEmpty)
                    Text(
                      'Alias: ${profile.alias}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: WatapColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      StatusChip(status: status, dense: true),
                      Text(
                        'Última consulta: '
                        '${formatRelativeTime(activity?.fetchedAtUnix)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: WatapColors.textSecondary,
                        ),
                      ),
                      if (activity?.fromCache == true)
                        const Text(
                          'Desde caché',
                          style: TextStyle(
                            fontSize: 11,
                            color: WatapColors.warning,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: refreshing ? 'Actualizando…' : 'Actualizar actividad',
              onPressed: refreshing
                  ? null
                  : () => controller.refreshProfile(profile.steamId64),
              icon: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más acciones',
              onSelected: (String value) =>
                  _handleAction(context, value, controller, profile),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Text('Editar alias'),
                ),
                const PopupMenuItem<String>(
                  value: 'steam',
                  child: Text('Abrir en Steam'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Eliminar integrante'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    String action,
    AppController controller,
    Profile profile,
  ) async {
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => AddEditProfileScreen(profile: profile),
          ),
        );
      case 'steam':
        await openExternalUrl(
          context,
          SteamApiUrls.communityProfile(profile.steamId64),
          action: 'abrir el perfil de Steam',
        );
      case 'delete':
        final ProfileActivity? activity = controller.activityFor(profile.steamId64);
        final bool hasData = activity?.games.isNotEmpty ?? false;
        final bool confirmed = await confirmAction(
          context,
          title: 'Eliminar integrante',
          message: hasData
              ? 'Se eliminará ${profile.displayName} y la actividad guardada '
                  'en la caché local.'
              : 'Se eliminará ${profile.displayName} de tu lista.',
        );
        if (!confirmed || !context.mounted) return;
        final OperationResult result =
            await controller.deleteProfile(profile.steamId64);
        if (context.mounted) {
          showMessage(context, result.messageEs, isError: !result.success);
        }
    }
  }
}