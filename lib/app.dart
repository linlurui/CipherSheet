import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/activation/activation_screen.dart';
import 'features/activation/mnemonic_wizard_screen.dart';
import 'features/ledgers/ledgers_screen.dart';
import 'features/security/lock_screen_dialogs.dart';
import 'state/app_state.dart';
import 'theme.dart';

class CipherSheetApp extends StatelessWidget {
  const CipherSheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CipherSheet',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 延迟检查启动时是否需要锁屏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenLock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appState = context.read<AppState>();
    // 移动端: paused, 桌面端: inactive/hidden
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      appState.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      appState.onAppResumed();
      _checkScreenLock();
    }
  }

  /// 检查并显示锁屏验证
  Future<void> _checkScreenLock() async {
    final state = context.read<AppState>();
    if (!state.screenLocked) return;
    if (!state.screenLock.isEnabled) return;

    // 显示验证对话框
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LockScreenVerifyDialog(service: state.screenLock),
    );

    if (result == true) {
      // 验证成功，解锁
      state.unlockScreen();
    } else {
      // 验证失败或取消，退出应用
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // 基础页面（根据 stage）
    Widget page;
    switch (state.stage) {
      case AppStage.booting:
        page = const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
        break;
      case AppStage.error:
        page = Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('初始化失败',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(state.errorMessage ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => state.boot(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        );
        break;
      case AppStage.needActivation:
        page = const ActivationScreen();
        break;
      case AppStage.ready:
        if (state.showMnemonicWizard) {
          page = const MnemonicWizardScreen();
        } else {
          page = const LedgersScreen();
        }
        break;
    }

    // 如果处于锁屏状态，添加模糊遮罩（验证对话框会显示在上方）
    if (state.screenLocked && state.screenLock.isEnabled) {
      return Stack(
        children: [
          page,
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 48, color: Colors.blue),
                      SizedBox(height: 16),
                      Text('应用已锁定'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return page;
  }
}
