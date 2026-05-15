#!/usr/bin/env dart
import 'dart:io';
import 'dart:ffi';
import 'package:path/path.dart' as p;
import 'package:decentrilicense/decentrilicense.dart';

// Global state
String? gSelectedProductKeyPath;
DecentriLicenseClient? gClient;
bool gInitialized = false;

void main(List<String> args) {
  try {
    if (args.isNotEmpty && args[0] == 'validate') {
      _quickValidate(args);
      return;
    }
    _interactiveWizard();
  } catch (e) {
    print('❌ 错误: $e');
    exit(1);
  }
}

void _quickValidate(List<String> args) {
  if (args.length < 3) {
    print('Usage: validation_wizard.dart validate <token_file> <product_public_key_file>');
    exit(1);
  }
  final tokenFile = args[1];
  final productKeyFile = args[2];

  final tokenContent = File(tokenFile).readAsStringSync();
  final productKeyContent = File(productKeyFile).readAsStringSync();

  final client = DecentriLicenseClient();
  try {
    client.initialize(udpPort: 13325, tcpPort: 23325);
    client.setProductPublicKey(productKeyContent);
    client.importToken(tokenContent);
    final result = client.offlineVerifyCurrentToken();

    if (result.valid) {
      print('✅ Token validation successful!');
      final status = client.getStatus();
      if (status.hasToken) {
        print('   Token ID: ${status.tokenId}');
        print('   License Code: ${status.licenseCode}');
        print('   App ID: ${status.appId}');
        print('   Holder Device: ${status.holderDeviceId}');
      }
      exit(0);
    } else {
      print('❌ Token validation failed: ${result.errorMessage}');
      exit(1);
    }
  } finally {
    client.shutdown();
  }
}

void _interactiveWizard() {
  print('\n🔐 DecentriLicense Flutter/Dart SDK 验证向导');
  print('=' * 50);

  while (true) {
    print('\n请选择操作:');
    print('1. 📥 导入令牌（密文/JSON）');
    print('2. ✅ 校验已激活令牌');
    print('3. 🔗 信任链验证');
    print('4. 📊 查询状态');
    print('5. 🔑 设置产品公钥');
    print('6. 📤 导出令牌');
    print('0. 🚪 退出');
    stdout.write('\n请选择 (0-6): ');

    final choice = stdin.readLineSync()?.trim() ?? '';
    switch (choice) {
      case '1': _importTokenWizard(); break;
      case '2': _verifyActivatedTokenWizard(); break;
      case '3': _trustChainValidationWizard(); break;
      case '4': _statusWizard(); break;
      case '5': _setProductKeyWizard(); break;
      case '6': _exportTokenWizard(); break;
      case '0':
        _cleanup();
        print('👋 再见！');
        return;
      default: print('❌ 无效的选择');
    }
  }
}

void _importTokenWizard() {
  print('\n📥 导入令牌');
  print('-' * 40);

  final tokenFile = _pickFile('请选择 token 文件:', ['.json', '.txt']);
  if (tokenFile == null) return;

  final tokenContent = File(tokenFile).readAsStringSync().trim();
  print('✅ 读取到令牌 (${tokenContent.length} 字符)');

  final client = _getOrCreateClient();
  if (client == null) return;

  // Set product public key
  final productKeyPath = _findProductPublicKey();
  if (productKeyPath != null) {
    try {
      final productKeyData = File(productKeyPath).readAsStringSync();
      client.setProductPublicKey(productKeyData);
      print('✅ 产品公钥设置成功');
    } catch (e) {
      print('❌ 设置产品公钥失败: $e');
      return;
    }
  }

  try {
    client.importToken(tokenContent);
    print('✅ 令牌导入成功');
  } catch (e) {
    print('❌ 导入令牌失败: $e');
    return;
  }

  // Activate
  print('🎯 正在激活令牌...');
  try {
    final result = client.activateBindDevice();
    if (result.valid) {
      print('✅ 激活成功');
    } else {
      print('❌ 激活失败: ${result.errorMessage}');
    }
  } catch (e) {
    print('❌ 激活失败: $e');
  }
}

void _verifyActivatedTokenWizard() {
  print('\n✅ 校验已激活令牌');
  print('-' * 40);

  final stateDir = Directory('.decentrilicense_state');
  if (!stateDir.existsSync()) {
    print('⚠️  没有找到已激活的令牌');
    return;
  }

  final activatedTokens = <String>[];
  print('\n📋 已激活的令牌列表:');
  int index = 1;
  for (final entry in stateDir.listSync()) {
    if (entry is Directory) {
      final name = p.basename(entry.path);
      activatedTokens.add(name);
      final stateFile = File(p.join(entry.path, 'current_state.json'));
      if (stateFile.existsSync()) {
        print('$index. $name ✅');
      } else {
        print('$index. $name ⚠️  (无状态文件)');
      }
      index++;
    }
  }

  if (activatedTokens.isEmpty) {
    print('⚠️  没有找到已激活的令牌');
    return;
  }

  stdout.write('\n请选择要验证的令牌 (1-${activatedTokens.length}): ');
  final choice = int.tryParse(stdin.readLineSync()?.trim() ?? '');
  if (choice == null || choice < 1 || choice > activatedTokens.length) {
    print('❌ 无效的选择');
    return;
  }

  final client = _getOrCreateClient();
  if (client == null) return;

  // Set product public key before verification
  final productKeyPath = gSelectedProductKeyPath ?? _findProductPublicKey();
  if (productKeyPath != null) {
    try {
      final productKeyData = File(productKeyPath).readAsStringSync();
      client.setProductPublicKey(productKeyData);
      print('✅ 产品公钥设置成功');
    } catch (e) {
      print('❌ 设置产品公钥失败: $e');
      return;
    }
  } else {
    print('❌ 未找到产品公钥文件，无法验证');
    return;
  }

  try {
    final result = client.offlineVerifyCurrentToken();
    if (result.valid) {
      print('✅ 令牌验证成功');
    } else {
      print('❌ 令牌验证失败: ${result.errorMessage}');
    }

    try {
      final status = client.getStatus();
      if (status.hasToken) {
        print('\n🎫 令牌信息:');
        print('   令牌ID: ${status.tokenId}');
        print('   许可证代码: ${status.licenseCode}');
        print('   应用ID: ${status.appId}');
        print('   持有设备ID: ${status.holderDeviceId}');
      }
    } catch (_) {}
  } catch (e) {
    print('❌ 验证失败: $e');
  }
}

void _trustChainValidationWizard() {
  print('\n🔗 信任链验证');
  print('-' * 40);
  print('💡 信任链验证检查加密签名的完整性：根密钥 → 产品公钥 → 令牌签名 → 设备绑定');

  final client = _getOrCreateClient();
  if (client == null) return;

  // Set product public key
  final productKeyPath = gSelectedProductKeyPath ?? _findProductPublicKey();
  if (productKeyPath != null) {
    try {
      final productKeyData = File(productKeyPath).readAsStringSync();
      client.setProductPublicKey(productKeyData);
      print('✅ 产品公钥设置成功');
    } catch (e) {
      print('❌ 设置产品公钥失败: $e');
      return;
    }
  }

  int checksPassed = 0;
  const totalChecks = 4;

  // Check 1: Token signature
  print('\n🔍 [1/$totalChecks] 验证令牌签名（根密钥 → 产品公钥 → 令牌）');
  try {
    final result = client.offlineVerifyCurrentToken();
    if (result.valid) {
      print('   ✅ 通过: 令牌签名有效，信任链完整');
      checksPassed++;
    } else {
      print('   ❌ 失败: ${result.errorMessage}');
    }
  } catch (e) {
    print('   ❌ 失败: $e');
  }

  // Check 2: Device state
  print('\n🔍 [2/$totalChecks] 验证设备状态');
  try {
    final deviceId = client.getDeviceId();
    if (deviceId.isNotEmpty) {
      print('   ✅ 通过: 设备状态正常 (设备ID: $deviceId)');
      checksPassed++;
    }
  } catch (e) {
    print('   ⚠️  警告: $e');
  }

  // Check 3: Holder matching
  print('\n🔍 [3/$totalChecks] 验证令牌持有者与当前设备匹配');
  try {
    final status = client.getStatus();
    final deviceId = client.getDeviceId();
    if (status.holderDeviceId == deviceId) {
      print('   ✅ 通过: 令牌持有者与当前设备匹配');
      checksPassed++;
    } else {
      print('   ⚠️  不匹配: 持有者=${status.holderDeviceId}, 设备=$deviceId');
    }
  } catch (e) {
    print('   ⚠️  警告: $e');
  }

  // Check 4: Token info
  print('\n🔍 [4/$totalChecks] 检查令牌详细信息');
  try {
    final status = client.getStatus();
    if (status.hasToken) {
      print('   ✅ 通过: 令牌信息完整');
      print('   🎫 令牌ID: ${status.tokenId}');
      print('   📝 许可证代码: ${status.licenseCode}');
      print('   📱 应用ID: ${status.appId}');
      checksPassed++;
    }
  } catch (e) {
    print('   ❌ 失败: $e');
  }

  print('\n📊 验证结果: $checksPassed/$totalChecks 通过');
  if (checksPassed == totalChecks) {
    print('✅ 所有检查通过！');
  } else {
    print('⚠️  部分检查未通过');
  }
}

void _statusWizard() {
  print('\n📊 查询状态');
  print('-' * 40);

  final client = _getOrCreateClient();
  if (client == null) return;

  try {
    final status = client.getStatus();
    print('has_token: ${status.hasToken ? 1 : 0}');
    print('is_activated: ${status.isActivated ? 1 : 0}');
    print('state_index: ${status.stateIndex}');
    print('token_id: ${status.tokenId}');
    print('holder_device_id: ${status.holderDeviceId}');
    print('app_id: ${status.appId}');
    print('license_code: ${status.licenseCode}');
  } catch (e) {
    print('❌ 查询状态失败: $e');
  }
}

void _setProductKeyWizard() {
  print('\n🔑 设置产品公钥');
  print('-' * 40);

  final keyFile = _pickFile('请选择产品公钥文件:', ['.pem']);
  if (keyFile == null) return;

  gSelectedProductKeyPath = keyFile;
  print('✅ 已选择产品公钥: $keyFile');

  final client = _getOrCreateClient();
  if (client == null) return;

  try {
    final content = File(keyFile).readAsStringSync();
    client.setProductPublicKey(content);
    print('✅ 产品公钥设置成功');
  } catch (e) {
    print('❌ 设置产品公钥失败: $e');
  }
}

void _exportTokenWizard() {
  print('\n📤 导出令牌');
  print('-' * 40);

  final client = _getOrCreateClient();
  if (client == null) return;

  print('请选择导出类型:');
  print('1. 导出当前令牌（加密）');
  print('2. 导出已激活令牌（加密）');
  print('3. 导出状态变更令牌（加密）');
  stdout.write('请选择 (1-3): ');

  final choice = stdin.readLineSync()?.trim() ?? '';
  String? result;
  String prefix;
  try {
    switch (choice) {
      case '1':
        result = client.exportCurrentTokenEncrypted();
        prefix = 'current';
        break;
      case '2':
        result = client.exportActivatedTokenEncrypted();
        prefix = 'activated';
        break;
      case '3':
        result = client.exportStateChangedTokenEncrypted();
        prefix = 'state_changed';
        break;
      default:
        print('❌ 无效的选择');
        return;
    }
  } catch (e) {
    print('❌ 导出失败: $e');
    return;
  }

  if (result != null && result.isNotEmpty) {
    final outFile = 'export_${prefix}_${DateTime.now().millisecondsSinceEpoch}.txt';
    File(outFile).writeAsStringSync(result);
    print('✅ 令牌已导出到: $outFile');
  } else {
    print('❌ 导出结果为空');
  }
}

// ============================================================
// Helper functions
// ============================================================

DecentriLicenseClient? _getOrCreateClient() {
  if (gClient != null && gInitialized) return gClient!;
  try {
    gClient = DecentriLicenseClient();
    gClient!.initialize(udpPort: 13325, tcpPort: 23325);
    gInitialized = true;
    return gClient;
  } catch (e) {
    print('❌ 创建客户端失败: $e');
    return null;
  }
}

void _cleanup() {
  if (gClient != null) {
    try { gClient!.shutdown(); } catch (_) {}
    gClient = null;
    gInitialized = false;
  }
}

String? _pickFile(String title, List<String> exts) {
  final dir = Directory.current;
  final files = dir.listSync()
      .whereType<File>()
      .where((f) => exts.any((ext) => f.path.toLowerCase().endsWith(ext)))
      .map((f) => p.basename(f.path))
      .toList()
      ..sort();

  print(title);
  if (files.isEmpty) {
    stdout.write('当前目录没有可选文件，请手动输入路径: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? null : input;
  }
  for (var i = 0; i < files.length; i++) {
    print('${i + 1}. ${files[i]}');
  }
  print('0. 手动输入路径');
  stdout.write('请选择文件编号: ');

  final sel = stdin.readLineSync()?.trim() ?? '';
  final n = int.tryParse(sel);
  if (n != null && n >= 1 && n <= files.length) {
    return p.join(dir.path, files[n - 1]);
  }
  stdout.write('请输入文件路径: ');
  final input = stdin.readLineSync()?.trim() ?? '';
  return input.isEmpty ? null : input;
}

String? _findProductPublicKey() {
  final dir = Directory.current;
  try {
    final files = dir.listSync()
        .whereType<File>()
        .where((f) {
          final name = p.basename(f.path).toLowerCase();
          return name.startsWith('public_') && name.endsWith('.pem');
        })
        .map((f) => f.path)
        .toList()
        ..sort();
    return files.isNotEmpty ? files.first : null;
  } catch (_) {
    return null;
  }
}
