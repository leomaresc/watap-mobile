/// Pantalla "Integrantes": lista de perfiles supervisados.
///
/// El flujo principal es **automático**: al conectar con Steam, la app lee el
/// grupo familiar (`IFamilyGroupsService`) y añade los integrantes con sus
/// nombres y avatares. La importación manual existe solo como respaldo.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../services/family_group_sync.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/ui_helpers.dart';
import '../onboarding/steam_connect_screen.dart';
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

    if (profiles.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            children: <Widget>[
              const Icon(Icons.groups_outlined, size: 48, color: WatapColors.accent),
              const SizedBox(height: 12),
              const Text(
                'Todavía no hay integrantes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WatapColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                controller.hasFamilyToken
                    ? 'Pulsa "Sincronizar grupo familiar" para que WATAP lea '
                        'los integrantes de tu familia en Steam y los añada '
                        'solos, con nombre y avatar.'
                    : 'Conecta tu cuenta de Steam para que WATAP lea tu grupo '
                        'familiar y añada los integrantes automáticamente.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: WatapColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: controller.hasFamilyToken
                    ? () => _sync(context, controller)
                    : () => _connect(context),
                icon: controller.hasFamilyToken
                    ? const Icon(Icons.sync)
                    : const Icon(Icons.link),
                label: Text(
                  controller.hasFamilyToken
                      ? 'Sincronizar grupo familiar'
                      : 'Conectar con Steam',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _openImport(context),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Importar a mano (respaldo)'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          _FamilyGroupCard(controller: controller),
          const SizedBox(height: 16),
          SectionCard(
            title: 'ACCIONES',
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Importar a mano (respaldo)'),
                subtitle: const Text(
                  'Pega una lista de SteamID64, URLs o nombres personalizados. '
                  'Solo si la conexión con Steam no funciona.',
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

  void _connect(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const SteamConnectScreen(),
      ),
    );
  }

  Future<void> _sync(BuildContext context, AppController controller) async {
    final FamilySyncOutcome outcome = await controller.syncFamilyGroup();
    if (!context.mounted) return;
    showMessage(context, outcome.messageEs, isError: !outcome.success);
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

/// Tarjeta con el estado del grupo familiar y sus acciones.
class _FamilyGroupCard extends StatelessWidget {
  const _FamilyGroupCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final bool connected = controller.hasFamilyToken;
    final bool syncing = controller.isSyncingFamily;

    return SectionCard(
      title: 'GRUPO FAMILIAR',
      subtitle: 'Los integrantes se leen de tu familia en Steam. No hace falta '
          'copiar enlaces a mano.',
      children: <Widget>[
        ListTile(
          leading: Icon(
            connected ? Icons.groups : Icons.link_off,
            color: connected ? WatapColors.success : WatapColors.warning,
          ),
          title: Text(
            connected
                ? ((controller.familyGroupName ?? '').trim().isEmpty
                    ? 'Conectado con Steam'
                    : 'Familia: ${controller.familyGroupName!.trim()}')
                : 'Sin conexión con Steam',
          ),
          subtitle: Text(
            connected
                ? 'Última sincronización: '
                    '${formatRelativeTime(controller.lastFamilySyncUnix)}'
                : 'Conecta tu cuenta para importar tus integrantes solos.',
          ),
        ),
        if (connected)
          ListTile(
            leading: syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.sync),
            title: Text(syncing ? 'Sincronizando…' : 'Sincronizar ahora'),
            subtitle: const Text('Vuelve a leer el grupo familiar en Steam'),
            enabled: !syncing,
            onTap: syncing ? null : () => _sync(context),
          )
        else
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Conectar con Steam'),
            subtitle: const Text(
              'Se abre la página oficial de Steam. Tu contraseña no pasa por '
              'WATAP.',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => const SteamConnectScreen(),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _sync(BuildContext context) async {
    final FamilySyncOutcome outcome = await controller.syncFamilyGroup();
    if (!context.mounted) return;
    showMessage(context, outcome.messageEs, isError: !outcome.success);
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