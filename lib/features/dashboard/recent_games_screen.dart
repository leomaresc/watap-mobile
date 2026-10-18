/// Pantalla "Recientes": juegos agrupados por integrante.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../services/activity_aggregator.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';
import 'member_activity_section.dart';
import 'member_detail_screen.dart';

/// Pantalla de actividad reciente por integrante.
class RecentGamesScreen extends StatefulWidget {
  const RecentGamesScreen({super.key});

  @override
  State<RecentGamesScreen> createState() => _RecentGamesScreenState();
}

class _RecentGamesScreenState extends State<RecentGamesScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    if (!controller.initialized) {
      return const LoadingState(message: 'Preparando los datos locales…');
    }

    if (controller.initializationError != null) {
      return ErrorStateView(controller: controller);
    }

    if (controller.profiles.isEmpty) {
      return EmptyState(
        title: 'Todavía no hay integrantes',
        message: 'WATAP carga los integrantes automáticamente desde tu grupo '
            'familiar de Steam. Ve a la sección Familia y sincroniza.',
        icon: Icons.person_add_alt_1_outlined,
        actionLabel: 'Ir a Familia',
        onAction: () {
          controller.setSection(AppSection.members);
        },
      );
    }

    final List<ProfileActivity> activities = controller.recentActivities;
    final Preferences prefs = controller.preferences;

    return Column(
      children: <Widget>[
        _SearchAndFilters(controller: controller, searchController: _searchController),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refreshAll,
            color: WatapColors.accent,
            backgroundColor: WatapColors.panel,
            child: activities.isEmpty
                ? ListView(
                    children: <Widget>[
                      SizedBox(
                        height: 260,
                        child: EmptyState(
                          title: 'Sin resultados',
                          message: 'Ningún integrante coincide con la búsqueda '
                              'actual. Borra el filtro para verlos todos.',
                          icon: Icons.search_off,
                          actionLabel: 'Limpiar filtros',
                          onAction: () {
                            _searchController.clear();
                            controller.setSearchQuery('');
                            controller.setFilterProfile(null);
                          },
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: activities.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ProfileActivity activity = activities[index];
                      final String name =
                          controller.displayNames[activity.steamId64] ??
                              activity.personaName ??
                              activity.steamId64;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: MemberActivitySection(
                          activity: activity,
                          displayName: name,
                          preferences: prefs,
                          isRefreshing: controller.isRefreshing(activity.steamId64),
                          onRefresh: () => controller.refreshProfile(activity.steamId64),
                          onOpenStore: (Game game) => _openStore(context, game),
                          onTapHeader: () => _openDetail(context, activity.steamId64),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openStore(BuildContext context, Game game) async {
    await openExternalUrl(
      context,
      SteamApiUrls.storePage(game.appId),
      action: 'abrir la página de Steam',
    );
  }

  Future<void> _openDetail(BuildContext context, String steamId64) async {
    // La pantalla de detalle lee el estado del controlador y no dispara
    // ninguna consulta de red por sí sola.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => MemberDetailScreen(steamId64: steamId64),
      ),
    );
  }
}

/// Vista de error de inicialización.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ErrorState(
      title: 'No se pudo abrir el almacenamiento local',
      message: controller.initializationError ??
          'Se ha producido un error desconocido al preparar la base de datos.',
      onRetry: controller.retryInitialize,
    );
  }
}

/// Búsqueda, filtro por integrante y ordenación.
class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.searchController,
  });

  final AppController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final List<Profile> profiles = controller.profiles;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: searchController,
            onChanged: controller.setSearchQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar juego o integrante',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: controller.searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar búsqueda',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        searchController.clear();
                        controller.setSearchQuery('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: controller.filterSteamId == null,
                  onSelected: (_) => controller.setFilterProfile(null),
                ),
                for (final Profile profile in profiles) ...<Widget>[
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(
                      profile.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: controller.filterSteamId == profile.steamId64,
                    onSelected: (bool selected) => controller.setFilterProfile(
                      selected ? profile.steamId64 : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<GameSortOrder>(
                  initialValue: controller.sortOrder,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Ordenar por',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: <DropdownMenuItem<GameSortOrder>>[
                    for (final GameSortOrder order in GameSortOrder.values)
                      DropdownMenuItem<GameSortOrder>(
                        value: order,
                        child: Text(
                          describeSortOrder(order),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (GameSortOrder? value) {
                    if (value != null) controller.setSortOrder(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Switch(
                      value: controller.preferences.hideLowActivity,
                      onChanged: (bool value) => controller.savePreferences(
                        controller.preferences.copyWith(hideLowActivity: value),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Ocultar poca actividad '
                        '(<${controller.preferences.lowActivityFilterMinutes} min)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: WatapColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
