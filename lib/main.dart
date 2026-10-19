/// Punto de entrada de WATAP Mobile.
///
/// No se incluye ninguna credencial. La única credencial es el token de sesión
/// de Steam, que cada usuario obtiene iniciando sesión y se guarda en el
/// almacenamiento seguro del dispositivo.
library;

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WatapBootstrap());
}
