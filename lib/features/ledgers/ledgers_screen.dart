import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/screen_lock_service.dart';
import '../../state/app_state.dart';
import '../ledger_detail/ledger_detail_screen.dart';
import '../ledger_detail/widgets/mnemonic_dialog.dart';
import '../security/lock_screen_dialogs.dart';

class LedgersScreen extends StatefulWidget {
  const LedgersScreen({super.key});

  @override
  State<LedgersScreen> createState() => _LedgersScreenState();
}

class _LedgersScreenState extends State<LedgersScreen>
    with TickerProviderStateMixin {
  late TabController _tabCtrl;
  int _tabCount = 1; // 至少1个"+"tab

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _syncTabs(int ledgerCount) {
    final newLen = ledgerCount + 1; // 账本tabs + 1个"+"tab
    if (newLen != _tabCount) {
      final prevIdx = _tabCtrl.index;
      _tabCtrl.dispose();
      _tabCount = newLen;
      _tabCtrl = TabController(
        length: _tabCount,
        vsync: this,
        initialIndex: prevIdx.clamp(0, _tabCount - 1),
      );
      setState(() {});
    }
  }

  Future<void> _openSecurityMenu(AppState state) async {
    final screenLock = ScreenLockService(storage: state.storage);
    await screenLock.load();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SecurityMenuDialog(
        mnemonicEnabled: state.mnemonicEnabled,
        isUnlocked: state.isUnlocked,
        lockType: screenLock.lockType,
        biometricEnabled: screenLock.biometricEnabled,
        canUseBiometric: () => screenLock.canCheckBiometrics(),
      ),
    );

    switch (result) {
      case 'mnemonic':
        await _openMnemonic(state);
        break;
      case 'lockscreen':
        await _openLockScreenSetup(screenLock);
        break;
      case 'license':
        await _openLicenseInfo(state);
        break;
    }
  }

  Widget _buildSecurityIcon(AppState state) {
    // 根据安全状态显示不同图标
    if (state.mnemonicEnabled) {
      return Icon(
        state.isUnlocked ? Icons.security : Icons.security_outlined,
        color: state.isUnlocked ? Colors.green : Colors.orange,
      );
    }
    return const Icon(Icons.security_outlined);
  }

  Future<void> _handleSecurityMenu(String value, AppState state) async {
    switch (value) {
      case 'mnemonic':
        await _openMnemonic(state);
        break;
      case 'lockscreen':
        await state.screenLock.load();
        await _openLockScreenSetup(state.screenLock);
        break;
      case 'license':
        await _openLicenseInfo(state);
        break;
    }
  }

  Future<void> _openMnemonic(AppState state) async {
    if (state.mnemonicEnabled) {
      if (state.isUnlocked) {
        // 已解锁：提供立即锁定
        final r = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('全局助记词'),
            content: const Text('助记词已启用，目前已解锁。所有加密金额可正常显示。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('立即锁定')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('关闭')),
            ],
          ),
        );
        if (r == true) state.lock();
      } else {
        // 已锁定：解锁
        final pass = await showDialog<String>(
          context: context,
          builder: (_) => const UnlockMnemonicDialog(),
        );
        if (pass == null || pass.isEmpty) return;
        final ok = await state.unlock(pass);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '已解锁' : '助记词错误')),
        );
      }
    } else {
      // 未启用：设置
      final pass = await showDialog<String>(
        context: context,
        builder: (_) => const SetMnemonicDialog(),
      );
      if (pass == null || pass.isEmpty) return;
      final err = await state.setMnemonic(pass);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? '助记词已设置，金额已二次加密')),
      );
    }
  }

  Future<void> _openLockScreenSetup(ScreenLockService service) async {
    await showDialog(
      context: context,
      builder: (ctx) => LockScreenSetupDialog(service: service),
    );
  }

  Future<void> _openLicenseInfo(AppState state) async {
    final s = state.license.safeStatus();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('授权状态'),
        content: Text(
          s == null
              ? '未连接'
              : 'Token ID: ${s.tokenId}\n'
                  'License: ${s.licenseCode}\n'
                  'App: ${s.appId}\n'
                  'state_index: ${s.stateIndex}\n'
                  'expire: ${DateTime.fromMillisecondsSinceEpoch(s.expireTime * 1000)}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteLedger(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账本'),
        content: Text('确定要删除账本「$name」吗？\n该操作将永久删除所有账单、格子和盘点记录，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await context.read<AppState>().deleteLedger(id);
  }

  Future<void> _createLedgerFromTemplate(BuildContext context) async {
    final state = context.read<AppState>();
    final views = state.ledgerViews();
    if (views.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有可用的模板账本')),
      );
      return;
    }

    // 选择模板账本
    String? selectedId;
    final nameCtrl = TextEditingController(
        text: '账本-${DateTime.now().millisecondsSinceEpoch % 10000}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新建模板账本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '新账本名称'),
              ),
              const SizedBox(height: 16),
              const Text('选择模板账本', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('请选择模板'),
                value: selectedId,
                items: views.map((v) => DropdownMenuItem(
                  value: v.ledger.id,
                  child: Text(v.ledger.name),
                )).toList(),
                onChanged: (v) => setState(() => selectedId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: selectedId == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || selectedId == null) return;
    await context.read<AppState>().createLedgerFromTemplate(
      name: nameCtrl.text.trim().isEmpty ? 'Untitled' : nameCtrl.text.trim(),
      templateLedgerId: selectedId!,
    );
  }

  Future<void> _createLedger(BuildContext context) async {
    final nameCtrl = TextEditingController(
        text: '账本-${DateTime.now().millisecondsSinceEpoch % 10000}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建账本'),
        content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().createLedger(
        name: nameCtrl.text.trim().isEmpty
            ? 'Untitled'
            : nameCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final views = state.ledgerViews();
    _syncTabs(views.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CipherSheet · 加密账本'),
        actions: [
          // 安全中心菜单（合并助记词、锁屏密码、激活信息）
          PopupMenuButton<String>(
            tooltip: '安全中心',
            icon: _buildSecurityIcon(state),
            onSelected: (value) => _handleSecurityMenu(value, state),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mnemonic',
                child: ListTile(
                  leading: Icon(
                    state.mnemonicEnabled
                        ? (state.isUnlocked ? Icons.lock_open : Icons.lock_outline)
                        : Icons.key_outlined,
                    color: state.mnemonicEnabled
                        ? (state.isUnlocked ? Colors.green : Colors.orange)
                        : Colors.grey,
                    size: 20,
                  ),
                  title: const Text('全局助记词'),
                  subtitle: Text(
                    state.mnemonicEnabled
                        ? (state.isUnlocked ? '已启用 · 已解锁' : '已启用 · 已锁定')
                        : '未设置',
                    style: const TextStyle(fontSize: 11),
                  ),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'lockscreen',
                child: ListTile(
                  leading: const Icon(Icons.screen_lock_portrait, size: 20),
                  title: const Text('锁屏密码'),
                  subtitle: const Text(
                    '6位密码 · 手势 · 生物识别',
                    style: TextStyle(fontSize: 11),
                  ),
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'license',
                child: const ListTile(
                  leading: Icon(Icons.shield_outlined, color: Colors.green, size: 20),
                  title: Text('激活信息'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            ...views.map((v) => Tab(
                  child: _LedgerTabLabel(
                    name: v.ledger.name,
                    mnemonicEnabled: v.mnemonicEnabled,
                    onDelete: () => _confirmDeleteLedger(v.ledger.id, v.ledger.name),
                  ),
                )),
            const Tab(icon: Icon(Icons.add, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          ...views.map((v) => LedgerDetailScreen(ledgerId: v.ledger.id)),
          // "+" tab: 创建账本引导
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.book_outlined, size: 48, color: Colors.black26),
                const SizedBox(height: 12),
                const Text('创建新账本',
                    style: TextStyle(color: Colors.black45)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _createLedger(context),
                  icon: const Icon(Icons.add),
                  label: const Text('新建空白账本'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _createLedgerFromTemplate(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('新建模板账本'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 账本 Tab 标签：鼠标悬停或选中时才显示删除图标
class _LedgerTabLabel extends StatefulWidget {
  final String name;
  final bool mnemonicEnabled;
  final VoidCallback onDelete;
  const _LedgerTabLabel({
    required this.name,
    required this.mnemonicEnabled,
    required this.onDelete,
  });

  @override
  State<_LedgerTabLabel> createState() => _LedgerTabLabelState();
}

class _LedgerTabLabelState extends State<_LedgerTabLabel> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onLongPress: widget.onDelete,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.mnemonicEnabled)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.key, size: 14, color: Colors.amber),
              ),
            Text(widget.name),
            if (_hovering) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onDelete,
                child: Icon(Icons.close, size: 14, color: Colors.red.shade400),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
