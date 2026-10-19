/// Pantalla de privacidad y almacenamiento local.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_helpers.dart';

/// Explica qué guarda WATAP, dónde y qué nunca se envía.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad y almacenamiento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const _Paragraph(
            title: 'Todo se guarda en tu dispositivo',
            body: 'WATAP no tiene servidores propios ni cuentas de usuario. Los '
                'perfiles que añades, su actividad, tus preferencias y los '
                'metadatos de caché se guardan en una base de datos SQLite '
                'privada del sistema de archivos de la aplicación.',
          ),
          const _Paragraph(
            title: 'Las credenciales viven en el almacén seguro',
            body: 'La clave de Steam Web API (opcional) y el token temporal de '
                'sesión se guardan con el almacén seguro de la plataforma '
                '(Keystore en Android, Keychain en iOS), bajo las referencias '
                '"${AppConstants.apiKeyStorageKey}" y '
                '"${AppConstants.steamTokenStorageKey}". Nunca se escriben en '
                'SQLite, en archivos JSON, en preferencias ordinarias, en los '
                'recursos de la aplicación ni en los registros.',
          ),
          const _Paragraph(
            title: 'Qué se envía y a dónde',
            body: 'Solo se realizan las solicitudes necesarias a la Steam Web API '
                '(${AppConstants.steamApiBaseUrl}), la carga de la página oficial '
                'de Steam en el WebView y las descargas de portadas y avatares '
                'desde el CDN público de imágenes de Steam. La clave viaja en el '
                'encabezado "${AppConstants.steamApiKeyHeader}"; el token de '
                'sesión viaja como parámetro de la URL sobre la conexión HTTPS '
                'directa a Steam (como hace la propia web de Steam) y nunca se '
                'registra.',
          ),
          const _Paragraph(
            title: 'Qué no incluye WATAP',
            body: 'No hay telemetría, analítica, publicidad, cuentas propias ni '
                'sincronización entre dispositivos. Tampoco se leen archivos '
                'locales de Steam del ordenador, ni cookies de sesión, ni la '
                'contraseña de Steam: el inicio de sesión ocurre únicamente en '
                'la página oficial de Valve dentro del WebView.',
          ),
          const _Paragraph(
            title: 'Permisos',
            body: 'La aplicación solo declara el permiso de acceso a Internet en '
                'Android. No solicita almacenamiento, ubicación, cámara, '
                'contactos ni notificaciones.',
          ),
          const _Paragraph(
            title: 'Datos de Steam',
            body: 'La información de perfiles y juegos pertenece a Steam. WATAP '
                'solo la muestra tal como la entrega la API pública. Un perfil '
                'privado puede impedir que Steam entregue los datos: en ese caso '
                'la aplicación lo indica y conserva lo que hubiera en la caché.',
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'ENLACES OFICIALES',
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Obtener una clave de Steam Web API'),
                subtitle: const Text(AppConstants.steamApiKeyRegistrationUrl),
                onTap: () => openExternalUrl(
                  context,
                  SteamApiUrls.apiKeyRegistration(),
                  action: 'abrir la página de registro',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Documentación de la Steam Web API'),
                subtitle: const Text(AppConstants.steamWebApiDocsUrl),
                onTap: () => openExternalUrl(
                  context,
                  Uri.parse(AppConstants.steamWebApiDocsUrl),
                  action: 'abrir la documentación',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacidad de tu perfil de Steam'),
                subtitle: const Text('steamcommunity.com/my/privacy'),
                onTap: () => openExternalUrl(
                  context,
                  Uri.parse('${AppConstants.steamCommunityBaseUrl}/my/privacy'),
                  action: 'abrir la configuración de privacidad de Steam',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Transparencia: el almacenamiento seguro protege la clave en reposo, '
            'pero ninguna aplicación cliente puede garantizar protección '
            'absoluta frente a un dispositivo comprometido o con ejecución '
            'instrumentada.',
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
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: WatapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: WatapColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
