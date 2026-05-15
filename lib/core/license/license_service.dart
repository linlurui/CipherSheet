import 'dart:io';

import 'package:decentrilicense/decentrilicense.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// DecentriLicense 封装。负责：
///  - 加载 dl-core 动态库（多路径搜索）
///  - 客户端初始化 + 产品公钥设置
///  - 激活（首次离线 token 字符串 / 已绑定恢复）
///  - 读写 state_payload（recordUsage）
///  - 助记词式 recovery channel
///  - 导出最新 token 字符串（便于备份）
class LicenseService {
  DecentriLicenseClient? _client;
  bool _ready = false;
  bool _activated = false;
  String? _libraryPath;
  String? _productKeyPem;

  bool get ready => _ready;
  /// 是否已激活（综合 FFI 状态 + 自身记录）
  bool get isActivated => _ready && (_activated || client.isActivated());
  DecentriLicenseClient get client {
    final c = _client;
    if (c == null) {
      throw StateError('LicenseService not initialized');
    }
    return c;
  }

  /// 候选 dylib/so/dll 搜索路径
  static List<String> _candidateLibraryPaths() {
    // iOS/Android 由 SDK 自身的 _loadLibrary 处理（iOS 静态链接，Android 走 jniLibs）
    if (Platform.isIOS || Platform.isAndroid) {
      return const [''];   // 空字符串表示走无参构造
    }
    final exeDir = File(Platform.executable).parent.path;
    String libName;
    if (Platform.isMacOS) {
      libName = 'libdecentrilicense.dylib';
    } else if (Platform.isLinux) {
      libName = 'libdecentrilicense.so';
    } else if (Platform.isWindows) {
      libName = 'decentrilicense.dll';
    } else {
      return [];
    }
    return <String>[
      // 应用 bundle 内常见位置
      p.join(exeDir, libName),
      p.join(exeDir, '..', 'Frameworks', libName),
      p.join(exeDir, '..', 'Resources', libName),
      // 开发期：直接指向 SDK 内嵌 dylib
      '/Volumes/workspace/project/ccait/dl-issuer/sdks/flutter/lib/native/$libName',
      '/Volumes/workspace/project/ccait/dl-issuer/sdks/flutter/lib/$libName',
      '/Volumes/workspace/project/ccait/dl-issuer/dl-core/build/$libName',
      // 系统 lookup
      libName,
    ];
  }

  Future<void> initialize({
    String licenseCode = '',
    String productKeyPem = '',
    int udpPort = 13325,
    int tcpPort = 23325,
    String registryServerUrl = '',
  }) async {
    if (_ready) return;
    Object? lastErr;
    for (final path in _candidateLibraryPaths()) {
      try {
        _client = path.isEmpty ||
                path == 'libdecentrilicense.dylib' ||
                path == 'libdecentrilicense.so' ||
                path == 'decentrilicense.dll'
            ? DecentriLicenseClient()
            : DecentriLicenseClient(libraryPath: path);
        _libraryPath = path;
        break;
      } catch (e) {
        lastErr = e;
        _client = null;
      }
    }
    if (_client == null) {
      throw LicenseException(
          '无法加载 dl-core 动态库，请确认 libdecentrilicense 已编译并放入应用同目录或 SDK lib/native/ 下。(last error: $lastErr)');
    }

    _client!.initialize(
      licenseCode: licenseCode,
      udpPort: udpPort,
      tcpPort: tcpPort,
      registryServerUrl: registryServerUrl,
    );

    if (productKeyPem.isNotEmpty) {
      _client!.setProductPublicKey(productKeyPem);
      _productKeyPem = productKeyPem;
    }

    _ready = true;
  }

  String? get libraryPath => _libraryPath;
  String? get productKeyPem => _productKeyPem;

  /// 当前状态
  StatusResult? safeStatus() {
    if (!_ready) return null;
    try {
      return client.getStatus();
    } catch (_) {
      return null;
    }
  }

  /// 用离线 token 字符串激活（首次激活 / 跨设备恢复）
  /// 加密 token (ciphertext|nonce): import_token → activate_bind_device
  /// JSON token: import_token → offline_verify
  ActivationResult activateWithToken(String tokenString) {
    final isEncrypted = tokenString.contains('|') &&
        tokenString.trim().split('|').length == 2;

    try {
      client.importToken(tokenString);
    } catch (e) {
      return ActivationResult(success: false, message: '导入 Token 失败: $e');
    }

    if (isEncrypted) {
      try {
        final result = client.activateBindDevice();
        if (result.valid) {
          _activated = true;
          return ActivationResult(success: true, message: '加密令牌激活成功');
        }
        return ActivationResult(
            success: false, message: result.errorMessage.isEmpty
                ? '绑定设备失败' : result.errorMessage);
      } catch (e) {
        return ActivationResult(success: false, message: '绑定设备失败: $e');
      }
    } else {
      try {
        final result = client.offlineVerifyCurrentToken();
        if (result.valid) {
          _activated = true;
          return ActivationResult(success: true, message: '激活成功');
        }
        return ActivationResult(
            success: false, message: result.errorMessage.isEmpty
                ? 'Token 验证失败' : result.errorMessage);
      } catch (e) {
        return ActivationResult(success: false, message: '验证失败: $e');
      }
    }
  }

  /// 重新绑定设备（导入后的二次激活路径）
  VerificationResult activateBindDevice() => client.activateBindDevice();

  /// 离线核验当前 token
  VerificationResult verify() => client.offlineVerifyCurrentToken();

  /// 写入状态（业务 payload JSON）。返回核验结果。
  VerificationResult recordUsage(String payloadJson) =>
      client.recordUsage(payloadJson);

  /// 读取明文 state_payload；为空返回空串
  String getStatePayload() {
    try {
      return client.getStatePayload();
    } catch (_) {
      return '';
    }
  }

  /// 导出最新带状态的 token（推荐每次写入后调用以便备份）
  String? safeExportStateChangedTokenEncrypted() {
    try {
      return client.exportStateChangedTokenEncrypted();
    } catch (_) {
      return null;
    }
  }

  /// 注册一个恢复通道（口令包裹 SEK）
  VerificationResult addRecoveryChannel(String password) =>
      client.addRecoveryChannel(password);

  VerificationResult removeRecoveryChannel() =>
      client.removeRecoveryChannel();

  /// 持久化 token 文件路径
  Future<File> _backupTokenFile() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'ciphersheet'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'token_latest.txt'));
  }

  /// 启动时尝试用磁盘备份 token 自动恢复激活
  /// 已激活则跳过；备份不存在或无效则返回 false
  Future<bool> tryRestoreFromBackup() async {
    if (!_ready) {
      print('[tryRestore] skipped: not ready');
      return false;
    }
    if (isActivated) {
      print('[tryRestore] already activated');
      return true;
    }
    try {
      final f = await _backupTokenFile();
      if (!await f.exists()) {
        print('[tryRestore] backup file not found: ${f.path}');
        return false;
      }
      final s = (await f.readAsString()).trim();
      if (s.isEmpty) {
        print('[tryRestore] backup file empty');
        return false;
      }
      print('[tryRestore] attempting restore, token length=${s.length}');
      // 备份 token 已绑定过本设备，先尝试 offline_verify（无需再次绑定）
      try {
        client.importToken(s);
      } catch (e) {
        print('[tryRestore] importToken failed: $e');
        return false;
      }
      // 先尝试离线验证（已绑定设备的情况）
      try {
        final v = client.offlineVerifyCurrentToken();
        if (v.valid) {
          print('[tryRestore] offline_verify succeeded');
          _activated = true;
          return true;
        }
        print('[tryRestore] offline_verify failed: ${v.errorMessage}');
      } catch (e) {
        print('[tryRestore] offline_verify exception: $e');
      }
      // 回退：尝试重新绑定（跨设备恢复场景）
      try {
        final v = client.activateBindDevice();
        if (v.valid) {
          print('[tryRestore] activate_bind_device succeeded');
          _activated = true;
          return true;
        }
        print('[tryRestore] activate_bind_device failed: ${v.errorMessage}');
      } catch (e) {
        print('[tryRestore] activate_bind_device exception: $e');
      }
      return false;
    } catch (e) {
      print('[tryRestore] exception: $e');
      return false;
    }
  }

  /// 备份原始 token 到应用支持目录（用于启动时自动恢复）
  Future<File?> backupRawTokenToDisk(String rawToken) async {
    if (rawToken.isEmpty) return null;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'ciphersheet'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = File(p.join(dir.path, 'token_latest.txt'));
    await f.writeAsString(rawToken);
    return f;
  }

  /// 备份导出的带状态 token（仅用于跨设备迁移，不用于本机恢复）
  Future<File?> backupTokenToDisk() async {
    final s = safeExportStateChangedTokenEncrypted();
    if (s == null || s.isEmpty) return null;
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'ciphersheet'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final f = File(p.join(dir.path, 'token_latest.txt'));
    await f.writeAsString(s);
    return f;
  }

  void shutdown() {
    try {
      _client?.shutdown();
    } catch (_) {}
    _client = null;
    _ready = false;
  }

  /// 读取备份 token 明文（供计算 hash 用）
  Future<String?> readBackupToken() async {
    try {
      final f = await _backupTokenFile();
      if (!await f.exists()) return null;
      final s = (await f.readAsString()).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }
}
