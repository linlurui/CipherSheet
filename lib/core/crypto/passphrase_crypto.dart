import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// 助记词派生 + AES-256-GCM 加解密。
///
/// 用途：在账本启用助记词时，对敏感字段（如账单金额、结算金额）做
/// **本地应用层二次加密**。该加密独立于 DecentriLicense Token 自身的
/// SEK/Recovery 机制——即使 Token 被导出，没有助记词也无法看到真实金额。
class PassphraseCrypto {
  static const int _saltLength = 16;     // 128-bit salt
  static const int _pbkdf2Iterations = 200000;
  static const int _keyLength = 32;      // 256-bit AES key
  static const int _nonceLength = 12;    // 96-bit GCM nonce

  static final _aes = AesGcm.with256bits();
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Iterations,
    bits: _keyLength * 8,
  );

  /// 由助记词派生 AES 密钥。
  static Future<SecretKey> deriveKey(String passphrase, List<int> salt) {
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  /// 生成随机 salt
  static List<int> randomSalt() {
    final r = Random.secure();
    return List<int>.generate(_saltLength, (_) => r.nextInt(256));
  }

  /// 生成助记词校验串：salt + PBKDF2(passphrase, salt) 的 base64，存于 LocalLedgerStore.mnemonicVerifier。
  /// 仅用于本地校验输入是否正确，不能反推助记词。
  static Future<String> buildVerifier(String passphrase) async {
    final salt = randomSalt();
    final key = await deriveKey(passphrase, salt);
    final keyBytes = await key.extractBytes();
    return '${base64Encode(salt)}:${base64Encode(keyBytes)}';
  }

  /// 校验助记词
  static Future<bool> verify(String passphrase, String verifier) async {
    final parts = verifier.split(':');
    if (parts.length != 2) return false;
    try {
      final salt = base64Decode(parts[0]);
      final expected = base64Decode(parts[1]);
      final key = await deriveKey(passphrase, salt);
      final actual = await key.extractBytes();
      if (actual.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < actual.length; i++) {
        diff |= actual[i] ^ expected[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  /// 加密任意字符串明文，返回 base64(salt|nonce|cipher|mac)
  static Future<String> encryptString(String plaintext, String passphrase) async {
    final salt = randomSalt();
    final key = await deriveKey(passphrase, salt);
    final nonce = AesGcm.with256bits().newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final buf = BytesBuilder();
    buf.add(salt);
    buf.add(nonce);
    buf.add(box.cipherText);
    buf.add(box.mac.bytes);
    return base64Encode(buf.toBytes());
  }

  /// 解密 encryptString 的产物。失败抛异常。
  static Future<String> decryptString(String cipherB64, String passphrase) async {
    final raw = base64Decode(cipherB64);
    if (raw.length < _saltLength + _nonceLength + 16) {
      throw const FormatException('Cipher payload too short');
    }
    final salt = raw.sublist(0, _saltLength);
    final nonce = raw.sublist(_saltLength, _saltLength + _nonceLength);
    final macStart = raw.length - 16;
    final cipher = raw.sublist(_saltLength + _nonceLength, macStart);
    final mac = Mac(raw.sublist(macStart));
    final key = await deriveKey(passphrase, salt);
    final clearBytes = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clearBytes);
  }

  /// 便捷：加密 double
  static Future<String> encryptDouble(double v, String passphrase) =>
      encryptString(v.toString(), passphrase);

  static Future<double> decryptDouble(String cipherB64, String passphrase) async {
    final s = await decryptString(cipherB64, passphrase);
    return double.parse(s);
  }
}
