import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/activation/activation_screen.dart';
import 'features/activation/mnemonic_wizard_screen.dart';
import 'features/ledgers/ledgers_screen.dart';
import 'core/security/screen_lock_service.dart';
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
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final appState = context.read<AppState>();
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.hidden) {
      appState.onAppPaused();
      // 进入后台时立刻遮挡，防止多任务截图泄露内容
      if (appState.screenLock.isEnabled) {
        setState(() => _obscured = true);
      }
    } else if (lifecycle == AppLifecycleState.resumed) {
      appState.onAppResumed();
      setState(() => _obscured = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // 锁屏只在 ready 状态生效，激活页/启动页不受锁屏控制
    if (state.stage == AppStage.ready &&
        state.screenLocked && state.screenLock.isEnabled) {
      return _LockScreen(service: state.screenLock, onUnlocked: state.unlockScreen);
    }

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
        // 过期前 3 天显示提醒 Banner
        final days = state.daysUntilExpiry;
        if (days != null && days > 0 && days <= 3 && !state.expiryWarningDismissed) {
          page = _ExpiryWarningWrapper(daysLeft: days, child: page);
        }
        break;
    }

    // 进入后台时用灰色遮挡，仅 ready 状态需要保护内容
    if (_obscured && state.stage == AppStage.ready) {
      return const Scaffold(backgroundColor: Color(0xFF2C2C2C));
    }

    return page;
  }
}

class _LockScreen extends StatefulWidget {
  final ScreenLockService service;
  final VoidCallback onUnlocked;
  const _LockScreen({required this.service, required this.onUnlocked});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showVerify());
  }

  Future<void> _showVerify() async {
    if (_dialogShown || !mounted) return;
    _dialogShown = true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LockScreenVerifyDialog(service: widget.service),
    );
    if (!mounted) return;
    if (result == true) {
      widget.onUnlocked();
    } else {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2C),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text('应用已锁定', style: TextStyle(fontSize: 16, color: Colors.white54)),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                _dialogShown = false;
                _showVerify();
              },
              icon: const Icon(Icons.lock_open, color: Colors.white70),
              label: const Text('解锁', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryWarningWrapper extends StatelessWidget {
  final int daysLeft;
  final Widget child;
  const _ExpiryWarningWrapper({required this.daysLeft, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.orange.shade700,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '授权码将在 $daysLeft 天后过期，请及时续费',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.read<AppState>().dismissExpiryWarning(),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
