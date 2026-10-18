/// Cifrado RSA con relleno PKCS#1 v1.5, implementado con `BigInt`.
///
/// Steam cifra la contraseña con su clave pública RSA antes de enviarla al
/// servicio de autenticación. No se usa ninguna dependencia externa: el relleno
/// y la exponenciación modular se resuelven con `BigInt`, que forma parte del
/// SDK de Dart.
///
/// Es una utilidad pura y por tanto se prueba en
/// `test/data/steam_rsa_test.dart` sin tocar la red.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Clave pública RSA tal como la entrega Steam (hexadecimal).
class SteamRsaPublicKey {
  const SteamRsaPublicKey({
    required this.modulusHex,
    required this.exponentHex,
  });

  final String modulusHex;
  final String exponentHex;

  BigInt get modulus => BigInt.parse(modulusHex, radix: 16);
  BigInt get exponent => BigInt.parse(exponentHex, radix: 16);

  /// Longitud en bytes de la clave (el tamaño del bloque cifrado).
  int get blockSize => (modulus.bitLength + 7) ~/ 8;
}

/// Cifra [message] con [publicKey] usando PKCS#1 v1.5 y devuelve Base64.
///
/// Se usa para cifrar la contraseña justo antes de enviarla. El texto cifrado
/// solo puede descifrarlo Steam; la contraseña en claro nunca se guarda.
String rsaEncryptPkcs1V15Base64(
  SteamRsaPublicKey publicKey,
  List<int> message,
) {
  final int k = publicKey.blockSize;
  if (message.length > k - 11) {
    throw ArgumentError(
      'El mensaje es demasiado largo para la clave RSA de ${k * 8} bits.',
    );
  }

  // Bloque con relleno PKCS#1 v1.5: 0x00 || 0x01 || PS || 0x00 || M
  final Uint8List block = Uint8List(k);
  block[0] = 0x00;
  block[1] = 0x01;
  final int paddingLength = k - 3 - message.length;
  for (int i = 0; i < paddingLength; i++) {
    block[2 + i] = 0xFF;
  }
  block[2 + paddingLength] = 0x00;
  block.setRange(2 + paddingLength + 1, k, message);

  final BigInt value = _bytesToBigInt(block);
  final BigInt encrypted = value.modPow(publicKey.exponent, publicKey.modulus);
  return base64.encode(_bigIntToBytes(encrypted, k));
}

/// Cifra una contraseña codificada en UTF-8.
String rsaEncryptPassword(SteamRsaPublicKey publicKey, String password) =>
    rsaEncryptPkcs1V15Base64(publicKey, utf8.encode(password));

BigInt _bytesToBigInt(List<int> bytes) {
  BigInt result = BigInt.zero;
  for (final int byte in bytes) {
    result = (result << 8) | BigInt.from(byte & 0xFF);
  }
  return result;
}

/// Convierte [value] en [length] bytes, rellenando por la izquierda con ceros.
Uint8List _bigIntToBytes(BigInt value, int length) {
  final Uint8List bytes = Uint8List(length);
  BigInt remaining = value;
  final BigInt mask = BigInt.from(0xFF);
  for (int i = length - 1; i >= 0; i--) {
    bytes[i] = (remaining & mask).toInt();
    remaining = remaining >> 8;
  }
  return bytes;
}
