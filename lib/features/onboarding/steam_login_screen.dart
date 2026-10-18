/// Inicio de sesión en Steam para leer el grupo familiar.
///
/// La contraseña no se guarda: se cifra con la clave pública de Steam y se
/// envía directamente a Steam. Lo único que se conserva (en el almacenamiento
/// seguro) son los tokens de sesión.
library;

import 'package:flutter/material.dart';

import '../../data/steam/steam_auth_client.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';

/// Estado del formulario de acceso.
enum _Phase {
  /// Esperando que el usuario escriba cuenta y contraseña.
  credentials,

  /// Steam ha pedido un código de Steam Guard.
  guardCode,

  /// Se está hablando con Steam.
  working,

  /// Esperando a que el usuario confirme desde su teléfono.
  confirmation,
}

/// Pantalla de acceso a Steam.
class SteamLoginScreen extends StatefulWidget {
  const SteamLoginScreen({super.key});

  @override
  State<SteamLoginScreen> createState() => _SteamLoginScreenState();
}

class _SteamLoginScreenState extends State<SteamLoginScreen> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  _Phase _phase = _Phase.credentials;
  SteamLoginChallenge? _challenge;
  String? _message;
  bool _messageIsError = false;
  bool _obscure = true;

  @override
  void dispose() {
    // La contraseña no debe quedarse en memoria al salir de la pantalla.
    _passwordController.clear();
    _codeController.clear();
    _accountController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
    if (controller.hasSteamSession && _phase == _Phase.credentials) {
      // Ya hay sesión: no tiene sentido volver a pedir credenciales.
      return Scaffold(
        appBar: AppBar(title: const Text('Cuenta de Steam')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: InlineNotice(
            message: 'Ya hay una sesión de Steam activa en este dispositivo.',
            icon: Icons.check_circle_outline,
            color: WatapColors.success,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión en Steam')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const InlineNotice(
            message: 'Steam solo entrega la lista de integrantes del grupo '
                'familiar a una sesión iniciada. Por eso hay que iniciar sesión '
                'una vez. La contraseña se cifra en el teléfono y se envía solo '
                'a Steam; WATAP no la guarda ni la muestra después.',
          ),
          const SizedBox(height: 16),
          if (_phase == _Phase.credentials) ..._credentialsFields(),
          if (_phase == _Phase.guardCode) ..._guardCodeFields(),
          if (_phase == _Phase.working || _phase == _Phase.confirmation) ..._waiting(),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 14),
            InlineNotice(
              message: _message!,
              icon: _messageIsError ? Icons.error_outline : Icons.info_outline,
              color: _messageIsError
                  ? WatapColors.activityHigh
                  : WatapColors.accent,
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Si tu cuenta tiene activada la confirmación en dos pasos, Steam te '
            'pedirá un código o te enviará una confirmación al teléfono. WATAP '
            'no puede saltarse ese paso.',
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

  List<Widget> _credentialsFields() {
    return <Widget>[
      Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            TextFormField(
              controller: _accountController,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta de Steam',
                helperText: 'El nombre con el que inicias sesión, no tu apodo.',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty)
                      ? 'Escribe el nombre de la cuenta.'
                      : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (String? value) =>
                  (value == null || value.isEmpty)
                      ? 'Escribe tu contraseña.'
                      : null,
              onFieldSubmitted: (_) => _start(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.login),
        label: const Text('Iniciar sesión en Steam'),
      ),
    ];
  }

  List<Widget> _guardCodeFields() {
    final bool email = _challenge?.guardCodeIsEmail ?? false;
    return <Widget>[
      Text(
        email
            ? 'Steam ha enviado un código a tu correo. Escríbelo aquí.'
            : 'Escribe el código que genera la aplicación móvil de Steam.',
        style: const TextStyle(
          fontSize: 13.5,
          color: WatapColors.textPrimary,
          height: 1.45,
        ),
      ),
      if (_challenge?.steamMessage != null) ...<Widget>[
        const SizedBox(height: 6),
        Text(
          _challenge!.steamMessage!,
          style: const TextStyle(
            fontSize: 12,
            color: WatapColors.textSecondary,
          ),
        ),
      ],
      const SizedBox(height: 14),
      TextField(
        controller: _codeController,
        autofocus: true,
        keyboardType: TextInputType.text,
        decoration: const InputDecoration(
          labelText: 'Código de Steam Guard',
          prefixIcon: Icon(Icons.shield_outlined),
        ),
        onSubmitted: (_) => _submitCode(),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _submitCode,
        icon: const Icon(Icons.check),
        label: const Text('Confirmar el código'),
      ),
    ];
  }

  List<Widget> _waiting() {
    return <Widget>[
      Row(
        children: <Widget>[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _phase == _Phase.confirmation
                  ? 'Esperando tu confirmación en el teléfono…'
                  : 'Consultando a Steam…',
              style: const TextStyle(
                fontSize: 13.5,
                color: WatapColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _start() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final AppController controller = AppScope.of(context);
    setState(() {
      _phase = _Phase.working;
      _message = null;
    });

    final SteamLoginStep step = await controller.beginSteamLogin(
      accountName: _accountController.text,
      password: _passwordController.text,
    );
    // La contraseña ya no hace falta: se borra del formulario en memoria.
    _passwordController.clear();

    if (!mounted) return;
    if (!step.success || step.challenge == null) {
      setState(() {
        _phase = _Phase.credentials;
        _message = step.messageEs;
        _messageIsError = true;
      });
      return;
    }

    _challenge = step.challenge;
    if (step.challenge!.needsGuardCode) {
      setState(() {
        _phase = _Phase.guardCode;
        _message = step.messageEs;
        _messageIsError = false;
      });
      return;
    }
    await _waitForConfirmation();
  }

  Future<void> _waitForConfirmation() async {
    final AppController controller = AppScope.of(context);
    setState(() {
      _phase = _Phase.confirmation;
      _message = null;
    });
    final OperationResult result =
        await controller.waitForSteamConfirmation(_challenge!);
    _finish(result, fallback: _Phase.credentials);
  }

  Future<void> _submitCode() async {
    final String code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _message = 'Escribe el código de Steam Guard.';
        _messageIsError = true;
      });
      return;
    }
    final AppController controller = AppScope.of(context);
    setState(() {
      _phase = _Phase.working;
      _message = null;
    });
    final OperationResult result = await controller.submitSteamGuardCode(
      challenge: _challenge!,
      code: code,
    );
    _codeController.clear();
    _finish(result, fallback: _Phase.guardCode);
  }

  void _finish(OperationResult result, {required _Phase fallback}) {
    if (!mounted) return;
    if (result.success) {
      showMessage(context, result.messageEs);
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _phase = fallback;
      _message = result.messageEs;
      _messageIsError = true;
    });
  }
}
