/// Pantalla de conexión con Steam mediante un `WebView`.
///
/// Abre la **página oficial de inicio de sesión de Steam** dentro de la
/// aplicación. El usuario escribe su contraseña en la página de Valve: nuestro
/// código nunca la ve ni la guarda.
///
/// Después del inicio de sesión, Steam redirige a un endpoint que devuelve JSON
/// con un `webapi_token` temporal. Ese token es la **única credencial** de la
/// app: permite leer el grupo familiar (`IFamilyGroupsService`) y la actividad
/// reciente.
///
/// El token se guarda en el almacenamiento seguro del dispositivo y se usa para
/// sincronizar los integrantes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/family_group_sync.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';

/// Página que devuelve el `webapi_token` de la sesión de la tienda.
///
/// Si la sesión no existe, Steam redirige a su formulario de acceso.
const String _tokenUrl =
    'https://store.steampowered.com/pointssummary/ajaxgetasyncconfig';

/// Formulario oficial de acceso, con vuelta al endpoint del token.
const String _loginUrl =
    'https://store.steampowered.com/login/?redir=%2Fpointssummary%2Fajaxgetasyncconfig';

/// Captura el token de la sesión de Steam desde la página abierta.
class SteamConnectScreen extends StatefulWidget {
  const SteamConnectScreen({super.key});

  @override
  State<SteamConnectScreen> createState() => _SteamConnectScreenState();
}

class _SteamConnectScreenState extends State<SteamConnectScreen> {
  late final WebViewController _web;

  /// Evita que varias cargas simultáneas disparen varias sincronizaciones.
  bool _handling = false;

  /// Evita pedir el endpoint del token en bucle.
  bool _requestedTokenPage = false;

  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // Fuera de Steam: no se sigue navegando.
            final Uri? uri = Uri.tryParse(request.url);
            final String host = uri?.host ?? '';
            if (host.isNotEmpty &&
                !host.endsWith('steamcommunity.com') &&
                !host.endsWith('steampowered.com')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) => unawaited(_onPageFinished()),
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
  }

  Future<void> _onPageFinished() async {
    if (_handling) return;

    if (await _extractToken()) return;

    // Sin token: puede que Steam haya redirigido a otra página tras acceder.
    if (!_requestedTokenPage) {
      final String url = await _web.currentUrl() ?? '';
      final bool looksLoggedIn = url.contains('store.steampowered.com') &&
          !url.contains('/login');
      if (looksLoggedIn) {
        _requestedTokenPage = true;
        await _web.loadRequest(Uri.parse(_tokenUrl));
      }
    }
  }

  /// Busca el `webapi_token` en el texto de la página cargada.
  Future<bool> _extractToken() async {
    Object? raw;
    try {
      raw = await _web.runJavaScriptReturningResult(
        "document.body ? document.body.innerText : ''",
      );
    } catch (_) {
      // Página sin cuerpo todavía: se reintenta en el próximo evento.
      return false;
    }

    final String text = _asText(raw);
    if (!text.contains('webapi_token')) return false;

    final Match? match =
        RegExp(r'"webapi_token"\s*:\s*"([^"]+)"').firstMatch(text);
    final String token = match?.group(1)?.trim() ?? '';
    if (token.isEmpty) return false;

    await _finishWithToken(token);
    return true;
  }

  Future<void> _finishWithToken(String token) async {
    if (_handling || !mounted) return;
    setState(() {
      _handling = true;
      _message = null;
      _messageIsError = false;
    });

    final AppController controller = AppScope.of(context);
    await controller.saveFamilyToken(token);
    final FamilySyncOutcome outcome = await controller.syncFamilyGroup();

    if (!mounted) return;
    setState(() {
      _handling = false;
      _message = outcome.messageEs;
      _messageIsError = !outcome.success;
    });

    // Mientras el token siga guardado, el paso se da por hecho aunque la
    // sincronización falle (cuenta sin familia, red caída…): la actividad se
    // consulta con el mismo token y se puede reintentar desde Integrantes.
    // Solo se permanece en esta pantalla si Steam rechazó el token (en cuyo
    // caso ya se ha borrado para no reintentar en vano).
    if (controller.hasFamilyToken) {
      unawaited(controller.refreshAll(silent: true));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(outcome.messageEs)));
      Navigator.of(context).pop(true);
    }
  }

  /// Normaliza el resultado de `runJavaScriptReturningResult`, que en algunas
  /// versiones devuelve la cadena entre comillas.
  static String _asText(Object? raw) {
    final String s = raw.toString();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      final String inner = s.substring(1, s.length - 1);
      return inner.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar con Steam')),
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: InlineNotice(
              message: 'Escribe tu cuenta y contraseña en la página oficial de '
                  'Steam. WATAP no ve ni guarda tu contraseña: solo obtiene un '
                  'token temporal para leer tu grupo familiar.',
              icon: Icons.lock_outline,
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: InlineNotice(
                message: _message!,
                icon: _messageIsError
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: _messageIsError
                    ? WatapColors.activityHigh
                    : WatapColors.success,
              ),
            ),
          if (_handling)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LoadingState(
                compact: true,
                message: 'Leyendo tu grupo familiar…',
              ),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: WatapColors.border),
              ),
              child: WebViewWidget(controller: _web),
            ),
          ),
        ],
      ),
    );
  }
}
