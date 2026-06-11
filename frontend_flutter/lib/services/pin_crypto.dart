part of solola_app;

class PinCrypto {
  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 200000,
    bits: 256,
  );

  static final AesGcm _aes = AesGcm.with256bits();

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }

  static Future<Map<String, dynamic>> encryptText({
    required String clearText,
    required String pin,
    required String hint,
    required String mode,
  }) async {
    final salt = randomBytes(16);
    final nonce = randomBytes(12);

    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );

    final secretBox = await _aes.encrypt(
      utf8.encode(clearText),
      secretKey: key,
      nonce: nonce,
    );

    final payload = <int>[...secretBox.cipherText, ...secretBox.mac.bytes];

    return {
      'encrypted': true,
      'mode': mode,
      'algorithm': 'AES-GCM',
      'kdf': 'PBKDF2',
      'iterations': 200000,
      'hint': hint,
      'salt': base64Encode(salt),
      'iv': base64Encode(nonce),
      'ciphertext': base64Encode(payload),
    };
  }

  static Future<String> decryptText({
    required Map<String, dynamic> payload,
    required String pin,
  }) async {
    final salt = base64Decode('${payload['salt']}');
    final nonce = base64Decode('${payload['iv']}');
    final encrypted = base64Decode('${payload['ciphertext']}');

    if (encrypted.length < 17) {
      throw Exception('Message chiffré invalide.');
    }

    final cipherText = encrypted.sublist(0, encrypted.length - 16);
    final macBytes = encrypted.sublist(encrypted.length - 16);

    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );

    final clearBytes = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
    );

    return utf8.decode(clearBytes);
  }
}
