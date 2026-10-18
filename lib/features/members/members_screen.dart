/// Pantalla "Familia": integrantes del grupo familiar de Steam.
///
/// La lista se llena sola a partir del grupo familiar. Aquí solo se editan
/// alias, se abre el perfil en Steam o, como excepción, se añade un perfil que
/// no pertenezca al grupo.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../services/family_group_sync.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/ui_helpers.dart';
import '../onboarding/steam_login_screen.dart';
import 'add_edit_profile_screen.dart';

/// Pantalla de integrantes del grupo familiar.
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

    final List<Profile> family = controller.familyMembers;
    final List<Profile> rescue = controller.rescueProfiles;

    if (!controller.hasSteamSession) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.link_off,
                  size: 42,
                  color: WatapColors.warning,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Sin sesión de Steam',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WatapColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Conecta tu cuenta para cargar los integrantes del grupo '
                  'familiar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: WatapColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => const SteamLoginScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar sesión en Steam'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: WatapColors.accent,
        foregroundColor: const Color(0xFF08202C),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Añadir a mano'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: <Widget>[
          _FamilyGroupCard(controller: controller),
          const SizedBox(height: 16),
          if (family.isEmpty)
            EmptyState(
              title: 'Todavía no hay integrantes',
              message: 'WATAP carga los integrantes automáticamente desde tu '
                  'grupo familiar de Steam. Pulsa "Sincronizar ahora" para '
                  'consultarlo.',
              icon: Icons.groups_outlined,
              actionLabel: 'Sincronizar ahora',
              onAction: () => _sync(context, controller),
            )
          else ...<Widget>[
            Text(
              'GRUPO FAMILIAR (${family.length})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WatapColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            for (final Profile profile in family)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberTile(controller: controller, profile: profile),
              ),
          ],
          if (rescue.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            const Text(
              'PERFILES AÑADIDOS A MANO',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WatapColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'No pertenecen a tu grupo familiar de Steam. Se mantienen solo '
              'porque los añadiste como excepción.',
              style: TextStyle(
                fontSize: 12,
                color: WatapColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            for (final Profile profile in rescue)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberTile(controller: controller, profile: profile),
              ),
          ],
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

  Future<void> _sync(BuildContext context, AppController controller) async {
    final FamilySyncOutcome outcome = await controller.syncFamilyGroup();
    if (!context.mounted) return;
    showMessage(context, outcome.messageEs, isError: !outcome.success);
  }
}

/// Tarjeta con el estado y las acciones del grupo familiar.
class _FamilyGroupCard extends StatelessWidget {
  const _FamilyGroupCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final bool syncing = controller.isSyncingFamily;
    final String? group = controller.familyGroupName;
    final int? lastSync = controller.lastFamilySyncUnix;

    return SectionCard(
      title: 'SINCRONIZACIÓN AUTOMÁTICA',
      subtitle: 'WATAP lee el grupo familiar de tu cuenta de Steam. No hace '
          'falta añadir integrantes uno a uno.',
      children: <Widget>[
        ListTile(
          leading: Icon(
            controller.hasSteamSession ? Icons.groups : Icons.link_off,
            color: controller.hasSteamSession
                ? WatapColors.success
                : WatapColors.warning,
          ),
          title: Text(
            group == null || group.trim().isEmpty
                ? (controller.hasSteamSession
                    ? 'Grupo familiar de ${controller.steamAccountName ?? 'tu cuenta'}'
                    : 'Sin sesión de Steam')
                : 'Grupo familiar: ${group.trim()}',
          ),
          subtitle: Text(
            '${controller.familyMembers.length} integrantes · '
            'Última sincronización: ${formatRelativeTime(lastSync)}',
          ),
        ),
        ListTile(
          leading: syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.sync),
          title: Text(syncing ? 'Sincronizando…' : 'Sincronizar ahora'),
          subtitle: const Text(
            'Vuelve a consultar a Steam los integrantes del grupo familiar',
          ),
          enabled: !syncing,
          onTap: syncing
              ? null
              : () async {
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
    final bool isOwn = profile.steamId64 == controller.steamId64;

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
                      if (isOwn)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.star,
                            size: 15,
                            color: WatapColors.activityModerate,
                            semanticLabel: 'Tu cuenta conectada',
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
        final String extra = profile.isFamilyMember
            ? ' Como pertenece a tu grupo familiar, la próxima sincronización '
                'volverá a añadirlo.'
            : '';
        final bool confirmed = await confirmAction(
          context,
          title: 'Eliminar integrante',
          message: (hasData
                  ? 'Se eliminará ${profile.displayName} y la actividad guardada '
                      'en la caché local.'
                  : 'Se eliminará ${profile.displayName} de tu lista.') +
              extra,
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
