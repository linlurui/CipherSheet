import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/state_chain_payload.dart';

/// 本地加密存储（账单/结算明细）。
///
/// 落盘文件：
///   <appSupportDir>/ciphersheet/store.aesgcm
///   <appSupportDir>/ciphersheet/device.key      (设备主密钥, 32B 随机)
///
/// 文件格式：[12B nonce][密文 + 16B GCM tag]
///
/// 注意：device.key 由 OS 文件权限保护；如需更高安全等级，
/// 可改为 keychain / DPAPI / libsecret 集成（后续可扩展）。
class LocalStore {
  static const _dirName = 'ciphersheet';
  static const _dataFile = 'store.aesgcm';
  static const _keyFile = 'device.key';
  static const _keyLength = 32;
  static const _nonceLength = 12;

  static final _aes = AesGcm.with256bits();

  Directory? _baseDir;
  SecretKey? _deviceKey;

  Future<Directory> _ensureBaseDir() async {
    if (_baseDir != null) return _baseDir!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _baseDir = dir;
    return dir;
  }

  Future<SecretKey> _ensureDeviceKey() async {
    if (_deviceKey != null) return _deviceKey!;
    final dir = await _ensureBaseDir();
    final keyFile = File(p.join(dir.path, _keyFile));
    if (await keyFile.exists()) {
      final raw = await keyFile.readAsBytes();
      if (raw.length == _keyLength) {
        _deviceKey = SecretKey(raw);
        return _deviceKey!;
      }
    }
    final r = Random.secure();
    final bytes =
        Uint8List.fromList(List<int>.generate(_keyLength, (_) => r.nextInt(256)));
    await keyFile.writeAsBytes(bytes, flush: true);
    try {
      // chmod 600 on POSIX
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', keyFile.path]);
      }
    } catch (_) {}
    _deviceKey = SecretKey(bytes);
    return _deviceKey!;
  }

  Future<File> _dataPath() async =>
      File(p.join((await _ensureBaseDir()).path, _dataFile));

  Future<LocalLedgerStore> load() async {
    final f = await _dataPath();
    if (!await f.exists()) return LocalLedgerStore.empty();
    final raw = await f.readAsBytes();
    if (raw.length < _nonceLength + 16) return LocalLedgerStore.empty();
    final nonce = raw.sublist(0, _nonceLength);
    final cipherAndMac = raw.sublist(_nonceLength);
    final macStart = cipherAndMac.length - 16;
    final cipher = cipherAndMac.sublist(0, macStart);
    final mac = Mac(cipherAndMac.sublist(macStart));
    final key = await _ensureDeviceKey();
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: mac),
        secretKey: key,
      );
      final j = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return LocalLedgerStore.fromJson(j);
    } catch (e) {
      // 文件损坏或被替换 —— 返回空，避免崩溃；上层可提示。
      return LocalLedgerStore.empty();
    }
  }

  Future<void> save(LocalLedgerStore store) async {
    final key = await _ensureDeviceKey();
    final nonce = _aes.newNonce();
    final payload = utf8.encode(jsonEncode(store.toJson()));
    final box = await _aes.encrypt(payload, secretKey: key, nonce: nonce);
    final buf = BytesBuilder();
    buf.add(nonce);
    buf.add(box.cipherText);
    buf.add(box.mac.bytes);
    final f = await _dataPath();
    // 原子写
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(buf.toBytes(), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> clear() async {
    final f = await _dataPath();
    if (await f.exists()) await f.delete();
  }

  Future<String> get debugBasePath async => (await _ensureBaseDir()).path;

  /// 暴露设备密钥字节（供 state_payload 加密用）
  Future<List<int>> deviceKeyBytes() async {
    final key = await _ensureDeviceKey();
    return key.extractBytes();
  }

  // ============================================================
  // 通用键值存储（用于锁屏密码等配置）
  // ============================================================
  
  Future<File> _keyValuePath(String key) async =>
      File(p.join((await _ensureBaseDir()).path, '$key.dat'));

  /// 读取通用键值数据
  Future<Uint8List?> read(String key) async {
    final f = await _keyValuePath(key);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  }

  /// 写入通用键值数据
  Future<void> write(String key, Uint8List data) async {
    final f = await _keyValuePath(key);
    await f.writeAsBytes(data, flush: true);
  }

  /// 删除通用键值数据
  Future<void> delete(String key) async {
    final f = await _keyValuePath(key);
    if (await f.exists()) await f.delete();
  }
}
