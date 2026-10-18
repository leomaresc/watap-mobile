/// Detalle de un integrante.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ui_helpers.dart';
import '../members/add_edit_profile_screen.dart';
import 'member_activity_section.dart';

/// Pantalla con la actividad completa de un integrante.
class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.steamId64});

  final String steamId64;

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
    final Profile? profile = controller.profileById(steamId64);

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Integrante')),
        body: const EmptyState(
          title: 'Integrante no encontrado',
          message: 'Es posible que se haya eliminado desde la lista de '
              'integrantes.',
          icon: Icons.person_off_outlined,
        ),
      );
    }

    final ProfileActivity activity = controller.activityFor(steamId64) ??
        ProfileActivity(
          steamId64: steamId64,
          personaName: profile.personaName,
          avatarUrl: profile.avatarUrl,
          status: FetchStatus.notFetched,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.displayName, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Editar integrante',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    AddEditProfileScreen(profile: profile),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: <Widget>[
          MemberActivitySection(
            activity: activity,
            displayName: profile.displayName,
            preferences: controller.preferences,
            isRefreshing: controller.isRefreshing(steamId64),
            onRefresh: () => controller.refreshProfile(steamId64),
            onOpenStore: (Game game) => openExternalUrl(
              context,
              SteamApiUrls.storePage(game.appId),
              action: 'abrir la página de Steam',
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'DATOS DEL PERFIL',
            children: <Widget>[
              _InfoRow(label: 'SteamID64', value: profile.steamId64),
              _InfoRow(
                label: 'Nombre público',
                value: profile.personaName ?? kUnknownValue,
              ),
              _InfoRow(label: 'Alias local', value: profile.alias ?? 'Sin alias'),
              _InfoRow(
                label: 'Añadido',
                value: formatLocalDateTime(profile.createdAtUnix),
              ),
              _InfoRow(
                label: 'Última consulta',
                value: formatLocalDateTime(activity.fetchedAtUnix),
              ),
              _InfoRow(
                label: 'Última consulta correcta',
                value: formatLocalDateTime(activity.lastSuccessAtUnix),
              ),
              _InfoRow(
                label: 'Origen de los datos',
                value: activity.fromCache ? 'Caché local' : 'Consulta directa',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'ACCIONES',
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Actualizar actividad'),
                subtitle: const Text(
                  'Consulta los juegos recientes de este integrante',
                ),
                onTap: () {
                  controller.refreshProfile(steamId64);
                  showMessage(
                    context,
                    'Actualizando ${profile.displayName}…',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Abrir perfil en Steam'),
                subtitle: Text(
                  SteamApiUrls.communityProfile(profile.steamId64).host,
                ),
                onTap: () => openExternalUrl(
                  context,
                  SteamApiUrls.communityProfile(profile.steamId64),
                  action: 'abrir el perfil de Steam',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: WatapColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: WatapColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
