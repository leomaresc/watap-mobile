/// Pantalla "Integrantes": administración de perfiles supervisados.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/ui_helpers.dart';
import '../dashboard/recent_games_screen.dart';
import 'add_edit_profile_screen.dart';
import 'friend_import_screen.dart';

/// Pantalla de administración de integrantes.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    if (!controller.initialized) {
      return const LoadingState(message: 'Preparando los datos locales…');
    }
    if (controller.initializationError != null) {
      return ErrorStateView(controller: controller);
    }

    if (controller.showingDemoData) {
      return _DemoMembersView(controller: controller);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: WatapColors.accent,
        foregroundColor: const Color(0xFF08202C),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Añadir'),
      ),
      body: controller.realProfiles.isEmpty
          ? EmptyState(
              title: 'Tu lista de integrantes está vacía',
              message: 'WATAP supervisa los perfiles que añadas manualmente. '
                  'Puedes añadirlos por SteamID64, por la URL de su perfil o por '
                  'su nombre personalizado de Steam.',
              icon: Icons.group_add_outlined,
              actionLabel: 'Añadir un integrante',
              onAction: () => _openForm(context),
              secondaryLabel: 'Probar el modo demostración',
              onSecondary: controller.enterDemoMode,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: <Widget>[
                const InlineNotice(
                  message: 'Esta lista es una selección personal. WATAP no '
                      'verifica que los integrantes pertenezcan a un mismo grupo '
                      'familiar de Steam.',
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'ACCIONES',
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1),
                      title: const Text('Añadir integrante'),
                      subtitle: const Text('Por SteamID64, URL o nombre personalizado'),
                      onTap: () => _openForm(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.group_add_outlined),
                      title: const Text('Importar amigos de Steam'),
                      subtitle: Text(
                        controller.hasApiKey
                            ? 'Requiere tu perfil propio marcado y una lista de '
                                'amigos accesible'
                            : 'Necesita una clave de Web API configurada',
                      ),
                      enabled: controller.hasApiKey,
                      onTap: controller.hasApiKey
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext _) =>
                                      const FriendImportScreen(),
                                ),
                              )
                          : null,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.science_outlined),
                      title: const Text('Modo demostración'),
                      subtitle: const Text(
                        'Muestra datos ficticios sin consultar Steam ni perder '
                        'tus perfiles',
                      ),
                      value: false,
                      onChanged: (_) => controller.enterDemoMode(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'INTEGRANTES (${controller.realProfiles.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WatapColors.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                for (final Profile profile in controller.realProfiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MemberTile(controller: controller, profile: profile),
                  ),
              ],
            ),
    );
  }

  void _openForm(BuildContext context, {Profile? profile}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => AddEditProfileScreen(profile: profile),
      ),
    );
  }
}

class _DemoMembersView extends StatelessWidget {
  const _DemoMembersView({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final List<Profile> demoProfiles = controller.profiles;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: <Widget>[
        const InlineNotice(
          message: 'MODO DEMOSTRACIÓN activo. Los perfiles que ves son '
              'ficticios y sus identificadores nunca se envían a Steam.',
          icon: Icons.science_outlined,
          color: WatapColors.warning,
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'SALIR DEL MODO DEMOSTRACIÓN',
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('Añadir un integrante real'),
              subtitle: const Text(
                'Al añadir tu primer perfil se desactiva la demostración',
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext _) => const AddEditProfileScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Desactivar el modo demostración'),
              subtitle: const Text(
                'Verás tu lista real de integrantes (puede estar vacía)',
              ),
              onTap: controller.exitDemoMode,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'PERFILES DE DEMOSTRACIÓN (${demoProfiles.length})',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: WatapColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        for (final Profile profile in demoProfiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    AvatarWidget(
                      displayName: profile.displayName,
                      isDemo: true,
                      size: 40,
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
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: WatapColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      WatapColors.warning.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'DEMO',
                                  style: TextStyle(
                                    color: WatapColors.warning,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SteamID64 reservado: ${profile.steamId64}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: WatapColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
                      if (profile.isOwnProfile)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.star,
                            size: 15,
                            color: WatapColors.activityModerate,
                            semanticLabel: 'Marcado como tu perfil',
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
                PopupMenuItem<String>(
                  value: 'own',
                  child: Text(
                    profile.isOwnProfile
                        ? 'Quitar marca de perfil propio'
                        : 'Marcar como mi perfil',
                  ),
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
      case 'own':
        await controller.setOwnProfile(
          profile.isOwnProfile ? null : profile.steamId64,
        );
        if (context.mounted) {
          showMessage(
            context,
            profile.isOwnProfile
                ? 'Se ha quitado la marca de perfil propio.'
                : 'Marcado como tu perfil. La API de Steam lo usará para la '
                    'importación de amigos.',
          );
        }
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
              ? 'Se eliminará ${profile.displayName} y la actividad guardada en '
                  'la caché local. Esta acción no se puede deshacer.'
              : 'Se eliminará ${profile.displayName} de tu lista de integrantes.',
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
