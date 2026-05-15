import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/license/license_service.dart';
import 'core/storage/local_store.dart';
import 'state/app_state.dart';

Future<String> _loadProductPublicKey() async {
  try {
    return await rootBundle.loadString('assets/keys/product_public_key.pem');
  } catch (_) {
    return '';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final license = LicenseService();
  final storage = LocalStore();
  final productKey = await _loadProductPublicKey();
  final state = AppState(license: license, storage: storage);
  // 异步引导
  // 不 await，让 UI 先出现 loading
  state.boot(productKeyPem: productKey);
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const CipherSheetApp(),
    ),
  );
}
