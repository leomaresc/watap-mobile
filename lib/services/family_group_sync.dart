/// Sincronización del grupo familiar de Steam con la base de datos local.
///
/// Usa el `webapi_token` de la sesión de Steam para leer
/// `IFamilyGroupsService` y reconciliar la lista local de perfiles.
///
/// Reglas de reconciliación (deliberadamente conservadoras):
/// - Nunca se borran integrantes si la respuesta no es utilizable. Un error de
///   red o una respuesta vacía **no** puede dejar la aplicación sin datos.
/// - Solo se retiran los perfiles marcados como `isFamilyMember` que ya no
///   aparezcan en la respuesta; los perfiles añadidos a mano se conservan.
/// - El alias local se preserva al actualizar.
library;

import '../core/models.dart';
import '../data/repositories/profiles_repository.dart';
import '../data/steam/family_groups_client.dart';
import '../data/steam/steam_api_client.dart';
import '../data/steam/steam_api_errors.dart';

/// Desenlace de una sincronización.
class FamilySyncOutcome {
  const FamilySyncOutcome({
    required this.success,
    required this.messageEs,
    this.groupName,
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.total = 0,
    this.requiresConnect = false,
    this.noGroup = false,
  });

  const FamilySyncOutcome.failure(
    this.messageEs, {
    this.requiresConnect = false,
    this.noGroup = false,
  })  : success = false,
        groupName = null,
        added = 0,
        updated = 0,
        removed = 0,
        total = 0;

  final bool success;
  final String messageEs;

  /// Nombre del grupo tal como lo devuelve Steam (puede faltar).
  final String? groupName;

  final int added;
  final int updated;
  final int removed;
  final int total;

  /// `true` cuando hace falta (re)conectar la cuenta de Steam.
  final bool requiresConnect;

  /// `true` cuando la cuenta no pertenece a ningún grupo familiar.
  final bool noGroup;
}

/// Servicio de sincronización del grupo familiar.
class FamilyGroupSyncService {
  FamilyGroupSyncService({
    required FamilyGroupsClient groups,
    required SteamApiClient api,
    required ProfilesRepository profiles,
  })  : _groups = groups,
        _api = api,
        _profiles = profiles;

  final FamilyGroupsClient _groups;
  final SteamApiClient _api;
  final ProfilesRepository _profiles;

  /// Consulta el grupo familiar y actualiza la lista de integrantes.
  Future<FamilySyncOutcome> sync(String accessToken) async {
    if (accessToken.trim().isEmpty) {
      return const FamilySyncOutcome.failure(
        'Conecta tu cuenta de Steam para leer el grupo familiar.',
        requiresConnect: true,
      );
    }

    try {
      final FamilyGroupForUser forUser =
          await _groups.getFamilyGroupForUser(accessToken);
      if (!forUser.hasGroup) {
        return const FamilySyncOutcome.failure(
          'Esta cuenta de Steam no pertenece a ningún grupo familiar. Crea uno '
          'en Steam (Familia) o conecta la cuenta que sí lo tenga.',
          noGroup: true,
        );
      }

      final FamilyGroup group = await _groups.getFamilyGroup(
        accessToken: accessToken,
        familyGroupId: forUser.familyGroupId!,
      );

      if (group.members.isEmpty) {
        // Respuesta no utilizable: no se borra nada.
        return const FamilySyncOutcome.failure(
          'Steam ha respondido con un grupo familiar sin integrantes. Tu lista '
          'no se ha modificado.',
        );
      }

      final Map<String, SteamPlayerSummary> summaries =
          await _loadSummaries(group.memberSteamIds);

      return await _reconcile(group: group, summaries: summaries);
    } on SteamApiException catch (e) {
      return FamilySyncOutcome.failure(
        e.messageEs,
        requiresConnect: e.kind == SteamApiErrorKind.invalidCredentials,
      );
    } catch (e) {
      return FamilySyncOutcome.failure(
        'No se pudo sincronizar el grupo familiar (${e.runtimeType}).',
      );
    }
  }

  Future<Map<String, SteamPlayerSummary>> _loadSummaries(
    List<String> steamIds,
  ) async {
    if (!_api.hasSteamAuth || steamIds.isEmpty) {
      return const <String, SteamPlayerSummary>{};
    }
    try {
      final List<SteamPlayerSummary> summaries =
          await _api.fetchPlayerSummaries(steamIds);
      return <String, SteamPlayerSummary>{
        for (final SteamPlayerSummary s in summaries) s.steamId64: s,
      };
    } on SteamApiException {
      // Los nombres y avatares son un extra: se importan igualmente los
      // integrantes y se completarán al actualizar la actividad.
      return const <String, SteamPlayerSummary>{};
    }
  }

  Future<FamilySyncOutcome> _reconcile({
    required FamilyGroup group,
    required Map<String, SteamPlayerSummary> summaries,
  }) async {
    final List<Profile> existing = await _profiles.loadAll();
    final Map<String, Profile> byId = <String, Profile>{
      for (final Profile p in existing) p.steamId64: p,
    };

    final Set<String> newIds = group.memberSteamIds.toSet();
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    int added = 0;
    int updated = 0;

    for (final String id in group.memberSteamIds) {
      final Profile? current = byId[id];
      final SteamPlayerSummary? summary = summaries[id];
      await _profiles.upsert(
        Profile(
          steamId64: id,
          personaName: summary?.personaName ?? current?.personaName,
          avatarUrl: summary?.avatarUrl ?? current?.avatarUrl,
          alias: current?.alias,
          isFamilyMember: true,
          createdAtUnix: current?.createdAtUnix ?? now + added,
        ),
      );
      if (current == null) {
        added++;
      } else {
        updated++;
      }
    }

    // Retirada de integrantes que ya no están en el grupo. Solo se eliminan
    // los que la propia aplicación marcó como familiares.
    int removed = 0;
    for (final Profile p in existing) {
      if (p.isFamilyMember && !newIds.contains(p.steamId64)) {
        await _profiles.delete(p.steamId64);
        removed++;
      }
    }

    final String label = (group.name ?? '').trim().isEmpty
        ? 'tu grupo familiar'
        : group.name!.trim();
    return FamilySyncOutcome(
      success: true,
      messageEs: _summaryMessage(
        groupLabel: label,
        added: added,
        updated: updated,
        removed: removed,
        total: group.members.length,
      ),
      groupName: group.name,
      added: added,
      updated: updated,
      removed: removed,
      total: group.members.length,
    );
  }

  static String _summaryMessage({
    required String groupLabel,
    required int added,
    required int updated,
    required int removed,
    required int total,
  }) {
    final List<String> parts = <String>[];
    if (added > 0) parts.add('$added nuevos');
    if (updated > 0) parts.add('$updated actualizados');
    if (removed > 0) parts.add('$removed retirados');
    final String detail = parts.isEmpty ? 'sin cambios' : parts.join(', ');
    return 'Grupo familiar "$groupLabel": $total integrantes ($detail).';
  }
}
