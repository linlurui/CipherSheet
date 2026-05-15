import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../storage/local_store.dart';

/// 锁屏方式枚举
enum LockType {
  none,       // 无锁屏
  pin6,       // 6位数字密码
  pattern,    // 手势密码
  biometric,  // 生物识别（指纹/面容）
}

/// 锁屏密码管理服务
class ScreenLockService {
  final LocalStore _storage;
  final LocalAuthentication _localAuth = LocalAuthentication();

  LockType _lockType = LockType.none;
  String? _pinHash;           // 6位密码哈希
  List<int>? _patternHash;    // 手势密码哈希（序列化）
  bool _biometricEnabled = false;

  ScreenLockService({required LocalStore storage}) : _storage = storage;

  LockType get lockType => _lockType;
  bool get isEnabled => _lockType != LockType.none;
  bool get biometricEnabled => _biometricEnabled;

  /// 从存储加载锁屏设置
  Future<void> load() async {
    final data = await _storage.read('screen_lock_config');
    if (data != null) {
      try {
        final json = jsonDecode(utf8.decode(data));
        _lockType = LockType.values[json['type'] ?? 0];
        _pinHash = json['pin_hash'];
        _biometricEnabled = json['biometric'] ?? false;
        final patternStr = json['pattern_hash'] as String?;
        if (patternStr != null) {
          _patternHash = base64Decode(patternStr);
        }
      } catch (e) {
        debugPrint('ScreenLock load error: $e');
      }
    }
  }

  /// 保存到存储
  Future<void> _save() async {
    final json = {
      'type': _lockType.index,
      'pin_hash': _pinHash,
      'biometric': _biometricEnabled,
      'pattern_hash': _patternHash != null ? base64Encode(_patternHash!) : null,
    };
    final data = utf8.encode(jsonEncode(json));
    await _storage.write('screen_lock_config', Uint8List.fromList(data));
  }

  /// 设置6位数字密码
  Future<bool> setPin6(String pin) async {
    if (pin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      return false;
    }
    _pinHash = _hashPin(pin);
    _lockType = LockType.pin6;
    await _save();
    return true;
  }

  /// 验证6位数字密码
  bool verifyPin6(String pin) {
    if (_pinHash == null) return false;
    return _hashPin(pin) == _pinHash;
  }

  /// 设置手势密码（3x3 网格，0-8 的序列）
  Future<bool> setPattern(List<int> pattern) async {
    if (pattern.length < 4) return false; // 至少4个点
    if (pattern.any((p) => p < 0 || p > 8)) return false;
    
    final bytes = Uint8List.fromList(pattern);
    _patternHash = sha256.convert(bytes).bytes;
    _lockType = LockType.pattern;
    await _save();
    return true;
  }

  /// 验证手势密码
  bool verifyPattern(List<int> pattern) {
    if (_patternHash == null) return false;
    final bytes = Uint8List.fromList(pattern);
    final hash = sha256.convert(bytes).bytes;
    return _listEquals(hash, _patternHash!);
  }

  /// 检查生物识别是否可用
  Future<bool> canCheckBiometrics() async {
    try {
      final available = await _localAuth.canCheckBiometrics;
      final deviceSupported = await _localAuth.isDeviceSupported();
      return available && deviceSupported;
    } on PlatformException catch (e) {
      debugPrint('Biometric check error: $e');
      return false;
    }
  }

  /// 获取可用的生物识别类型
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      debugPrint('Get biometrics error: $e');
      return [];
    }
  }

  /// 启用/禁用生物识别
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      // 先验证是否可用
      final canUse = await canCheckBiometrics();
      if (!canUse) return false;
    }
    _biometricEnabled = enabled;
    await _save();
    return true;
  }

  /// 生物识别认证
  Future<bool> authenticateBiometric({String? reason}) async {
    if (!_biometricEnabled) return false;
    try {
      final result = await _localAuth.authenticate(
        localizedReason: reason ?? '请验证身份以解锁应用',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: $e');
      return false;
    }
  }

  /// 清除所有锁屏设置
  Future<void> clear() async {
    _lockType = LockType.none;
    _pinHash = null;
    _patternHash = null;
    _biometricEnabled = false;
    await _storage.delete('screen_lock_config');
  }

  /// 更改密码（需要先验证旧密码）
  Future<bool> changePin6(String oldPin, String newPin) async {
    if (!verifyPin6(oldPin)) return false;
    return setPin6(newPin);
  }

  Future<bool> changePattern(List<int> oldPattern, List<int> newPattern) async {
    if (!verifyPattern(oldPattern)) return false;
    return setPattern(newPattern);
  }

  /// 密码哈希
  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
