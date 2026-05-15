import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// state_payload 加解密工具。
///
/// 写入 DecentriLicense Token 的 payload 必须加密（不能明文）。
/// 使用设备固定密钥（32B）做 AES-256-GCM，格式：
///   base64( salt[16] | nonce[12] | cipherText | mac[16] )
///
/// 导出/导入场景：用用户密码通过 PBKDF2 派生密钥加密。
class PayloadCrypto {
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static final _aes = AesGcm.with256bits();

  // ---- 设备密钥模式（自动，同设备加解密）----

  /// 用设备密钥加密 payload JSON → base64 字符串
  static Future<String> encryptWithDeviceKey(
      String plaintext, List<int> deviceKeyBytes) async {
    final key = SecretKey(deviceKeyBytes);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final buf = BytesBuilder();
    buf.add(nonce);
    buf.add(box.cipherText);
    buf.add(box.mac.bytes);
    return base64Encode(buf.toBytes());
  }

  /// 用设备密钥解密 → 明文 JSON
  static Future<String> decryptWithDeviceKey(
      String cipherB64, List<int> deviceKeyBytes) async {
    final raw = base64Decode(cipherB64);
    if (raw.length < _nonceLen + 16) {
      throw const FormatException('Encrypted payload too short');
    }
    final nonce = raw.sublist(0, _nonceLen);
    final macStart = raw.length - 16;
    final cipher = raw.sublist(_nonceLen, macStart);
    final mac = Mac(raw.sublist(macStart));
    final key = SecretKey(deviceKeyBytes);
    final clear = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  // ---- 密码模式（导入/导出）----

  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 200000,
    bits: 256,
  );

  /// 用密码加密 payload JSON → base64
  static Future<String> encryptWithPassphrase(
      String plaintext, String passphrase) async {
    final salt = _randomBytes(_saltLen);
    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final nonce = _aes.newNonce();
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

  /// 用密码解密 → 明文 JSON
  static Future<String> decryptWithPassphrase(
      String cipherB64, String passphrase) async {
    final raw = base64Decode(cipherB64);
    if (raw.length < _saltLen + _nonceLen + 16) {
      throw const FormatException('Encrypted export too short');
    }
    final salt = raw.sublist(0, _saltLen);
    final nonce = raw.sublist(_saltLen, _saltLen + _nonceLen);
    final macStart = raw.length - 16;
    final cipher = raw.sublist(_saltLen + _nonceLen, macStart);
    final mac = Mac(raw.sublist(macStart));
    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final clear = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  static List<int> _randomBytes(int len) {
    final r = Random.secure();
    return List<int>.generate(len, (_) => r.nextInt(256));
  }
}
