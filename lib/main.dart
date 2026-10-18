/// Punto de entrada de WATAP Mobile.
///
/// No se incluye ninguna clave de API. La clave la introduce cada usuario y se
/// guarda en el almacenamiento seguro del dispositivo.
library;

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WatapBootstrap());
}
