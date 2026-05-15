import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/payload_crypto.dart';
import '../core/crypto/passphrase_crypto.dart';
import '../core/license/license_service.dart';
import '../core/security/screen_lock_service.dart';
import '../core/storage/local_store.dart';
import '../core/sync/lan_sync_service.dart';
import '../models/bill.dart';
import '../models/cell.dart';
import '../models/ledger.dart';
import '../models/settlement.dart';
import '../models/state_chain_payload.dart';

enum AppStage { booting, needActivation, ready, error }

class AppState extends ChangeNotifier {
  final LicenseService license;
  final LocalStore storage;
  final _uuid = const Uuid();

  AppStage stage = AppStage.booting;
  String? errorMessage;

  /// 是否需要显示助记词向导（首次激活后）
  bool showMnemonicWizard = false;

  /// 全局助记词明文（仅在内存，解锁后填充）
  String? _globalPassphrase;
  String? _lastRawToken; // 用户原始输入的 token，用于备份恢复
  String? _activationHash; // 激活码唯一 hash（用于设备识别）
  LanSyncService? _syncService;

  /// 锁屏服务（延迟初始化）
  late final ScreenLockService screenLock = ScreenLockService(storage: storage);

  /// 应用是否处于锁屏状态（需要用户验证才能使用）
  bool _screenLocked = false;
  bool get screenLocked => _screenLocked;

  /// 后台时间戳，用于超时判定
  DateTime? _backgroundAt;
  static const Duration _lockTimeout = Duration(minutes: 1);

  /// 全局助记词是否已解锁
  bool get isUnlocked => _globalPassphrase != null;

  /// 全局助记词是否已启用
  bool get mnemonicEnabled => _store.mnemonicEnabled;

  LocalLedgerStore _store = LocalLedgerStore.empty();
  LocalLedgerStore get store => _store;

  AppState({required this.license, required this.storage});

  Future<void> boot({
    String licenseCode = '',
    String productKeyPem = '',
  }) async {
    try {
      stage = AppStage.booting;
      notifyListeners();

      await license.initialize(
        licenseCode: licenseCode,
        productKeyPem: productKeyPem,
      );
      print('[boot] license initialized, activated=${license.isActivated}');

      _store = await storage.load();
      print('[boot] store loaded, ledgers=${_store.ledgers.length}');

      // 加载锁屏设置，冷启动时若已设置则进入锁屏状态
      await screenLock.load();
      if (screenLock.isEnabled) {
        _screenLocked = true;
        print('[boot] screen locked (type=${screenLock.lockType})');
      }

      // 若未激活，尝试用上次备份的 token 静默恢复
      bool restored = false;
      if (!license.isActivated) {
        restored = await license.tryRestoreFromBackup();
        print('[boot] tryRestore result=$restored, activated=${license.isActivated}');
      }

      if (license.isActivated || restored) {
        // 从备份 token 计算 hash
        final backupToken = await license.readBackupToken();
        if (backupToken != null) {
          _activationHash = _computeActivationHash(backupToken);
          _lastRawToken = backupToken;
        }
        await _restoreFromTokenIfNeeded();
        stage = AppStage.ready;
        print('[boot] stage=ready');
        // 启动局域网同步
        _startLanSync();
      } else {
        stage = AppStage.needActivation;
        print('[boot] stage=needActivation');
      }
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      stage = AppStage.error;
      notifyListeners();
    }
  }

  Future<String?> activateWithToken(String tokenStr) async {
    try {
      final r = license.activateWithToken(tokenStr);
      if (!r.success) return r.message;
      _lastRawToken = tokenStr;
      _activationHash = _computeActivationHash(tokenStr);
      await _restoreFromTokenIfNeeded();
      // 首次激活后标记需要助记词向导
      showMnemonicWizard = true;
      stage = AppStage.ready;
      notifyListeners();
      // 备份原始 token 以便下次启动自动恢复
      await license.backupRawTokenToDisk(tokenStr);
      // 启动局域网同步
      _startLanSync();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void dismissMnemonicWizard() {
    showMnemonicWizard = false;
    notifyListeners();
  }

  Future<void> _restoreFromTokenIfNeeded() async {
    final raw = license.getStatePayload();
    if (raw.trim().isEmpty) return;

    // 尝试解密（新格式：base64 密文）
    String plainJson;
    try {
      final keyBytes = await storage.deviceKeyBytes();
      plainJson = await PayloadCrypto.decryptWithDeviceKey(raw, keyBytes);
    } catch (_) {
      // 兼容旧版：可能是明文 JSON
      plainJson = raw;
    }

    final parsed = StateChainPayload.tryParse(plainJson);
    if (parsed == null) return;

    final localIds = _store.ledgers.map((l) => l.id).toSet();
    for (final l in parsed.ledgers) {
      if (!localIds.contains(l.id)) {
        _store.ledgers.add(l);
        _store.bills.putIfAbsent(l.id, () => []);
        _store.settlements.putIfAbsent(l.id, () => []);
      }
    }
  }

  // ============================================================
  // Ledger CRUD
  // ============================================================

  List<LedgerView> ledgerViews() {
    return _store.ledgers.map((l) {
      final bills = List<Bill>.from(_store.bills[l.id] ?? const [])
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final settlements = List<Settlement>.from(_store.settlements[l.id] ?? const []);
      settlements.sort((a, b) => b.settleTime.compareTo(a.settleTime));
      return LedgerView(
        ledger: l,
        bills: bills,
        latestSettlement: settlements.isEmpty ? null : settlements.first,
        settlementHistory: settlements,
        mnemonicEnabled: _store.mnemonicEnabled,
        unlocked: isUnlocked,
      );
    }).toList();
  }

  LedgerView? ledgerView(String id) {
    final l = _store.ledgers.firstWhere((x) => x.id == id,
        orElse: () => Ledger(id: '', name: '', interestRate: 0));
    if (l.id.isEmpty) return null;
    final bills = List<Bill>.from(_store.bills[l.id] ?? const [])
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final settlements = List<Settlement>.from(_store.settlements[l.id] ?? const []);
    settlements.sort((a, b) => b.settleTime.compareTo(a.settleTime));
    return LedgerView(
      ledger: l,
      bills: bills,
      latestSettlement: settlements.isEmpty ? null : settlements.first,
      settlementHistory: settlements,
      mnemonicEnabled: _store.mnemonicEnabled,
      unlocked: isUnlocked,
    );
  }

  Future<Ledger> createLedger({
    required String name,
    double interestRate = 0,
    double? warningLimit,
    double warningLimitPercent = 2.0,
  }) async {
    final l = Ledger(
      id: _uuid.v4(),
      name: name,
      interestRate: interestRate,
      warningLimitPercent: warningLimitPercent,
      warningLimitOverride: warningLimit,
    );
    _store.ledgers.add(l);
    _store.bills[l.id] = [];
    _store.settlements[l.id] = [];
    await _persistAndChain('create_ledger', {'ledger_id': l.id});
    return l;
  }

  /// 从已有账本复制配置（参数、公式、账单结构、单元格结构），不含记账/盘点/结算记录
  Future<Ledger> createLedgerFromTemplate({
    required String name,
    required String templateLedgerId,
  }) async {
    final templateBills = _store.bills[templateLedgerId] ?? [];
    final templateLedger = _store.ledgers.firstWhere((l) => l.id == templateLedgerId);

    final newLedgerId = _uuid.v4();
    final l = Ledger(
      id: newLedgerId,
      name: name,
      interestRate: templateLedger.interestRate,
      warningLimitPercent: templateLedger.warningLimitPercent,
      warningLimitOverride: templateLedger.warningLimitOverride,
      parameters: templateLedger.parameters
          .map((p) => LedgerParameter(key: p.key, value: p.value, unit: p.unit))
          .toList(),
      formulas: Map.from(templateLedger.formulas),
    );

    // 复制账单和单元格（不含记录）
    final newBills = templateBills.map((bill) {
      final newBillId = _uuid.v4();
      final newCells = bill.cells.map((cell) {
        return Cell(
          cellId: _uuid.v4(),
          billId: newBillId,
          orderIndex: cell.orderIndex,
          title: cell.title,
          multiplier: cell.multiplier,
          formula: cell.formula,
          parameters: cell.parameters
              .map((p) => CellParameter(key: p.key, value: p.value, unit: p.unit))
              .toList(),
          // 不复制 records / settlementEvent / settlementAmount / encryptedAmount
        );
      }).toList();

      return Bill(
        billId: newBillId,
        ledgerId: newLedgerId,
        orderIndex: bill.orderIndex,
        title: bill.title,
        cells: newCells,
      );
    }).toList();

    _store.ledgers.add(l);
    _store.bills[newLedgerId] = newBills;
    _store.settlements[newLedgerId] = [];
    await _persistAndChain('create_ledger_from_template', {
      'ledger_id': newLedgerId,
      'template_ledger_id': templateLedgerId,
    });
    return l;
  }

  Future<void> renameLedger(String id, String newName) async {
    final l = _store.ledgers.firstWhere((x) => x.id == id);
    l.name = newName;
    l.updatedAt = DateTime.now();
    await _persistAndChain('rename_ledger', {'ledger_id': id});
  }

  Future<void> deleteLedger(String id) async {
    _store.ledgers.removeWhere((x) => x.id == id);
    _store.bills.remove(id);
    _store.settlements.remove(id);
    await _persistAndChain('delete_ledger', {'ledger_id': id});
  }

  Future<void> updateLedgerSettings(String id,
      {double? interestRate, double? warningLimit, double? warningLimitPercent}) async {
    final l = _store.ledgers.firstWhere((x) => x.id == id);
    if (interestRate != null) l.interestRate = interestRate;
    if (warningLimitPercent != null) l.warningLimitPercent = warningLimitPercent;
    if (warningLimit != null) l.warningLimitOverride = warningLimit;
    l.updatedAt = DateTime.now();
    await _persistAndChain('update_ledger_settings', {'ledger_id': id});
  }

  /// 更新账本级参数（可增减）
  Future<void> updateLedgerParameters(
      String id, List<LedgerParameter> parameters) async {
    final l = _store.ledgers.firstWhere((x) => x.id == id);
    l.parameters = List.from(parameters);
    l.updatedAt = DateTime.now();
    await _persistAndChain('update_ledger_parameters', {'ledger_id': id});
  }

  /// 更新账本级公式（盘点事件 -> 表达式）
  Future<void> updateLedgerFormulas(
      String id, Map<String, String> formulas) async {
    final l = _store.ledgers.firstWhere((x) => x.id == id);
    l.formulas = Map.from(formulas);
    l.updatedAt = DateTime.now();
    await _persistAndChain('update_ledger_formulas', {'ledger_id': id});
  }

  /// 更新账本级盘点公式（盘盈/盘亏各一个）
  Future<void> updateLedgerFormula(String id, Map<String, String> formulas) async {
    final l = _store.ledgers.firstWhere((x) => x.id == id);
    l.formulas = Map.from(formulas);
    l.updatedAt = DateTime.now();
    await _persistAndChain('update_ledger_formula', {'ledger_id': id});
  }

  /// 更新账本规则
  Future<void> updateLedgerRules(String id, LedgerRules rules) async {
    final l = _store.ledgers.firstWhere((x) => x.id == id);
    l.rules = rules;
    l.updatedAt = DateTime.now();
    await _persistAndChain('update_ledger_rules', {'ledger_id': id});
  }

  // ============================================================
  // 全局助记词
  // ============================================================

  /// 设置全局助记词（首次或重新设置）
  Future<String?> setMnemonic(String mnemonic) async {
    if (_store.mnemonicEnabled) {
      return '助记词已设置，请先清除后再重新设置';
    }
    final verifier = await PassphraseCrypto.buildVerifier(mnemonic);
    _store.mnemonicVerifier = verifier;
    _store.mnemonicEnabled = true;
    _globalPassphrase = mnemonic;

    // 对所有账本已有格子的 amount 做加密迁移
    for (final ledgerId in _store.bills.keys) {
      final bills = _store.bills[ledgerId] ?? [];
      for (final bill in bills) {
        for (var ci = 0; ci < bill.cells.length; ci++) {
          final cell = bill.cells[ci];
          final cipher = await PassphraseCrypto.encryptDouble(cell.totalAmount, mnemonic);
          bill.cells[ci] = cell.copyWith(encryptedAmount: cipher);
        }
      }
    }

    try {
      license.addRecoveryChannel(mnemonic);
    } catch (_) {}

    await _persistAndChain('enable_mnemonic', {});
    return null;
  }

  /// 全局解锁助记词
  Future<bool> unlock(String mnemonic) async {
    if (!_store.mnemonicEnabled || _store.mnemonicVerifier == null) return true;
    final ok = await PassphraseCrypto.verify(mnemonic, _store.mnemonicVerifier!);
    if (!ok) return false;
    _globalPassphrase = mnemonic;

    // 解密所有账本格子的 amount 到内存视图
    for (final ledgerId in _store.bills.keys) {
      final bills = _store.bills[ledgerId] ?? [];
      for (final bill in bills) {
        for (var ci = 0; ci < bill.cells.length; ci++) {
          final cell = bill.cells[ci];
          if (cell.encryptedAmount != null) {
            try {
              final v = await PassphraseCrypto.decryptDouble(cell.encryptedAmount!, mnemonic);
              if (cell.records.isNotEmpty) {
                cell.records[0].amount = v;
              }
            } catch (_) {}
          }
        }
      }
    }
    notifyListeners();
    return true;
  }

  /// 全局锁定（清除内存中的助记词）
  void lock() {
    _globalPassphrase = null;
    notifyListeners();
  }

  // ============================================================
  // Bill CRUD (账单/表格)
  // ============================================================

  String _defaultBillTitle(int index) =>
      index.toString().padLeft(2, '0');

  Future<Bill> addBill(String ledgerId, {String? title}) async {
    final bills = _store.bills.putIfAbsent(ledgerId, () => []);
    final nextIndex =
        bills.isEmpty ? 1 : (bills.map((b) => b.orderIndex).reduce((a, b) => a > b ? a : b) + 1);
    final b = Bill(
      billId: _uuid.v4(),
      ledgerId: ledgerId,
      orderIndex: nextIndex,
      title: title?.isNotEmpty == true ? title! : _defaultBillTitle(nextIndex),
    );
    bills.add(b);
    await _persistAndChain('add_bill', {'ledger_id': ledgerId, 'bill_id': b.billId});
    return b;
  }

  Future<List<Bill>> batchAddBills(String ledgerId, int count) async {
    final created = <Bill>[];
    final bills = _store.bills.putIfAbsent(ledgerId, () => []);
    var nextIndex =
        bills.isEmpty ? 1 : (bills.map((b) => b.orderIndex).reduce((a, b) => a > b ? a : b) + 1);
    for (var i = 0; i < count; i++) {
      final b = Bill(
        billId: _uuid.v4(),
        ledgerId: ledgerId,
        orderIndex: nextIndex,
        title: _defaultBillTitle(nextIndex),
      );
      bills.add(b);
      created.add(b);
      nextIndex++;
    }
    await _persistAndChain('batch_add_bills', {'ledger_id': ledgerId, 'count': count});
    return created;
  }

  Future<void> renameBill(String ledgerId, String billId, String newTitle) async {
    final bills = _store.bills[ledgerId] ?? [];
    final idx = bills.indexWhere((b) => b.billId == billId);
    if (idx < 0) return;
    bills[idx] = bills[idx].copyWith(title: newTitle);
    await _persistAndChain('rename_bill', {'ledger_id': ledgerId, 'bill_id': billId});
  }

  Future<void> deleteBill(String ledgerId, String billId) async {
    final bills = _store.bills[ledgerId] ?? [];
    bills.removeWhere((b) => b.billId == billId);
    await _persistAndChain('delete_bill', {'ledger_id': ledgerId, 'bill_id': billId});
  }

  // ============================================================
  // Cell CRUD (格子)
  // ============================================================

  String _defaultCellTitle(int index) =>
      index.toString().padLeft(2, '0');

  Future<Cell> addCell(String ledgerId, String billId,
      {String? title, double multiplier = 1.0, String formula = ''}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) throw StateError('Bill not found');
    final bill = bills[billIdx];
    final nextIndex =
        bill.cells.isEmpty ? 1 : (bill.cells.map((c) => c.orderIndex).reduce((a, b) => a > b ? a : b) + 1);

    // 从账本全局参数复制默认值到单元格参数
    final ledger = _store.ledgers.firstWhere((l) => l.id == ledgerId);
    final defaultParams = ledger.parameters
        .map((p) => CellParameter(key: p.key, value: p.value, unit: p.unit))
        .toList();

    var c = Cell(
      cellId: _uuid.v4(),
      billId: billId,
      orderIndex: nextIndex,
      title: title?.isNotEmpty == true ? title! : _defaultCellTitle(nextIndex),
      multiplier: multiplier,
      formula: formula,
      parameters: defaultParams,
    );
    c = await _maybeEncryptCell(c);
    bill.cells.add(c);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('add_cell', {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': c.cellId});
    return c;
  }

  Future<List<Cell>> batchAddCells(String ledgerId, String billId, int count) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) throw StateError('Bill not found');
    final bill = bills[billIdx];
    final created = <Cell>[];
    var nextIndex =
        bill.cells.isEmpty ? 1 : (bill.cells.map((c) => c.orderIndex).reduce((a, b) => a > b ? a : b) + 1);

    // 从账本全局参数复制默认值到单元格参数
    final ledger = _store.ledgers.firstWhere((l) => l.id == ledgerId);
    final defaultParams = ledger.parameters
        .map((p) => CellParameter(key: p.key, value: p.value, unit: p.unit))
        .toList();

    for (var i = 0; i < count; i++) {
      var c = Cell(
        cellId: _uuid.v4(),
        billId: billId,
        orderIndex: nextIndex,
        title: _defaultCellTitle(nextIndex),
        parameters: defaultParams.map((p) => CellParameter(key: p.key, value: p.value, unit: p.unit)).toList(),
      );
      c = await _maybeEncryptCell(c);
      bill.cells.add(c);
      created.add(c);
      nextIndex++;
    }
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('batch_add_cells', {'ledger_id': ledgerId, 'bill_id': billId, 'count': count});
    return created;
  }

  Future<void> updateCell(String ledgerId, String billId, Cell updated) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == updated.cellId);
    if (cellIdx < 0) return;
    bill.cells[cellIdx] = await _maybeEncryptCell(updated);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('update_cell',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': updated.cellId});
  }

  Future<void> deleteCell(String ledgerId, String billId, String cellId) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    bill.cells.removeWhere((c) => c.cellId == cellId);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('delete_cell',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  // ============================================================
  // CellRecord CRUD (格子记账记录)
  // ============================================================

  Future<void> addCellRecord(String ledgerId, String billId, String cellId,
      {required double amount, String remarks = ''}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    cell.records.add(CellRecord(
      recordId: _uuid.v4(),
      amount: amount,
      timestamp: DateTime.now(),
      remarks: remarks,
    ));
    cell.updatedAt = DateTime.now();
    bill.cells[cellIdx] = await _maybeEncryptCell(cell);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('add_cell_record',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  Future<void> updateCellRecord(String ledgerId, String billId, String cellId,
      CellRecord updated) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    final recIdx = cell.records.indexWhere((r) => r.recordId == updated.recordId);
    if (recIdx < 0) return;
    cell.records[recIdx] = updated;
    cell.updatedAt = DateTime.now();
    bill.cells[cellIdx] = await _maybeEncryptCell(cell);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('update_cell_record',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  Future<void> deleteCellRecord(String ledgerId, String billId, String cellId,
      String recordId) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    cell.records.removeWhere((r) => r.recordId == recordId);
    cell.updatedAt = DateTime.now();
    bill.cells[cellIdx] = await _maybeEncryptCell(cell);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('delete_cell_record',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  // ============================================================
  // CellParameter CRUD (动态参数增删)
  // ============================================================

  Future<void> addCellParameter(String ledgerId, String billId, String cellId,
      {required String key, required double value, String unit = ''}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    cell.parameters.add(CellParameter(key: key, value: value, unit: unit));
    cell.updatedAt = DateTime.now();
    bill.cells[cellIdx] = cell.copyWith();
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('add_cell_param',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId, 'param_key': key});
  }

  Future<void> updateCellParameter(String ledgerId, String billId, String cellId,
      String key, {double? value, String? unit}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    final pIdx = cell.parameters.indexWhere((p) => p.key == key);
    if (pIdx < 0) return;
    if (value != null) cell.parameters[pIdx].value = value;
    if (unit != null) cell.parameters[pIdx].unit = unit;
    cell.updatedAt = DateTime.now();
    bill.cells[cellIdx] = cell.copyWith();
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('update_cell_param',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId, 'param_key': key});
  }

  /// 批量更新单元格参数（替换整个参数列表）
  Future<void> updateCellParameters(String ledgerId, String billId, String cellId,
      {required List<CellParameter> parameters}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    bill.cells[cellIdx] = cell.copyWith(parameters: parameters);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('update_cell_params',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  Future<void> deleteCellParameter(String ledgerId, String billId, String cellId,
      String key) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    cell.parameters.removeWhere((p) => p.key == key);
    cell.updatedAt = DateTime.now();
    bill.cells[cellIdx] = cell.copyWith();
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('delete_cell_param',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId, 'param_key': key});
  }

  Future<void> setCellFormula(String ledgerId, String billId, String cellId,
      String formula) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    bill.cells[cellIdx] = cell.copyWith(formula: formula);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('set_cell_formula',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  // ============================================================
  // 格子加密辅助
  // ============================================================

  Future<Cell> _maybeEncryptCell(Cell c) async {
    if (!_store.mnemonicEnabled || _globalPassphrase == null) return c;
    final cipher = await PassphraseCrypto.encryptDouble(c.totalAmount, _globalPassphrase!);
    return c.copyWith(encryptedAmount: cipher);
  }

  // ============================================================
  // Cell-level Settlement (盘点/结算)
  // ============================================================

  Future<void> markCellSettled(String ledgerId, String billId, String cellId,
      {required String event, required double amount}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    bill.cells[cellIdx] = cell.copyWith(
      settlementEvent: event,
      settlementAmount: amount,
    );
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('mark_cell_settled',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  Future<void> setCellSettledAmount(String ledgerId, String billId, String cellId,
      {required double amount}) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    bill.cells[cellIdx] = cell.copyWith(settledAmount: amount);
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('set_cell_settled_amount',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  Future<void> resetCellSettlement(String ledgerId, String billId, String cellId) async {
    final bills = _store.bills[ledgerId] ?? [];
    final billIdx = bills.indexWhere((b) => b.billId == billId);
    if (billIdx < 0) return;
    final bill = bills[billIdx];
    final cellIdx = bill.cells.indexWhere((c) => c.cellId == cellId);
    if (cellIdx < 0) return;
    final cell = bill.cells[cellIdx];
    bill.cells[cellIdx] = cell.copyWith(
      settlementEvent: null,
      settlementAmount: null,
      settledAmount: null,
      clearSettlement: true,
    );
    bills[billIdx] = bill.copyWith();
    await _persistAndChain('reset_cell_settlement',
        {'ledger_id': ledgerId, 'bill_id': billId, 'cell_id': cellId});
  }

  // ============================================================
  // Settlement
  // ============================================================

  Future<Settlement> settle(String ledgerId, double inputAmount) async {
    final view = ledgerView(ledgerId)!;
    final l = view.ledger;

    final total = view.totalAmount();
    final expected = view.expectedAmount();
    final interest = expected - total;
    final diff = inputAmount - expected;

    // 收集每个格子金额快照用于绘图
    final cellAmounts = <double>[];
    for (final bill in view.bills) {
      for (final cell in bill.sortedCells) {
        cellAmounts.add(cell.totalAmount);
      }
    }

    String? encryptedInput;
    if (_store.mnemonicEnabled && _globalPassphrase != null) {
      encryptedInput = await PassphraseCrypto.encryptDouble(inputAmount, _globalPassphrase!);
    }

    final s = Settlement(
      settlementId: _uuid.v4(),
      ledgerId: ledgerId,
      settleTime: DateTime.now(),
      inputAmount: inputAmount,
      interestRate: l.interestRate,
      expectedAmount: expected,
      calculatedInterest: interest,
      diff: diff,
      encryptedInputAmount: encryptedInput,
      cellAmountsSnapshot: cellAmounts,
      billCount: view.bills.length,
      cellCount: view.totalCellCount,
    );
    final list = _store.settlements.putIfAbsent(ledgerId, () => []);
    list.add(s);
    await _persistAndChain('settle', {'ledger_id': ledgerId, 'settlement_id': s.settlementId});
    return s;
  }

  // ============================================================
  // 持久化 + 上链
  // ============================================================

  /// 检查激活是否过期，过期则跳转激活页
  bool _checkActivation() {
    if (!license.isActivated) {
      stage = AppStage.needActivation;
      notifyListeners();
      return false;
    }
    return true;
  }

  /// 计算激活码唯一 hash（SHA-256 前 16 字节 hex）
  String _computeActivationHash(String rawToken) {
    final bytes = utf8.encode(rawToken);
    // 简单 hash：用 SHA-256 的前 16 字节转 hex
    // 注意：dart:crypto 不在 Flutter 标准库，用简单替代
    var h = 0;
    for (var i = 0; i < bytes.length; i++) {
      h = ((h << 5) - h + bytes[i]) & 0xFFFFFFFF;
    }
    // 用 token 的前 64 字节 + 长度做更唯一标识
    final buf = Uint8List(68);
    for (var i = 0; i < 64 && i < bytes.length; i++) {
      buf[i] = bytes[i];
    }
    buf[64] = (bytes.length >> 24) & 0xFF;
    buf[65] = (bytes.length >> 16) & 0xFF;
    buf[66] = (bytes.length >> 8) & 0xFF;
    buf[67] = bytes.length & 0xFF;
    // FNV-1a hash
    var hash = 0x811c9dc5;
    for (final b in buf) {
      hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 获取当前激活 hash（供同步识别用）
  String? get activationHash => _activationHash;

  /// 获取同步服务状态
  LanSyncService? get syncService => _syncService;

  /// 启动局域网同步
  void _startLanSync() {
    if (_activationHash == null) return;
    _syncService?.stop();
    _syncService = LanSyncService(
      activationHash: _activationHash!,
      onExportRequest: () => exportEncrypted(_activationHash!),
      onImportRequest: (data) => importEncrypted(data, _activationHash!),
    );
    _syncService!.lastUpdated = _latestUpdatedAt();
    _syncService!.start();
  }

  /// 获取所有账本中最新的 updatedAt
  DateTime _latestUpdatedAt() {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final l in _store.ledgers) {
      if (l.updatedAt.isAfter(latest)) latest = l.updatedAt;
    }
    for (final billList in _store.bills.values) {
      for (final b in billList) {
        for (final c in b.cells) {
          if (c.updatedAt.isAfter(latest)) latest = c.updatedAt;
        }
      }
    }
    return latest;
  }

  Future<void> _persistAndChain(String action, Map<String, dynamic> meta) async {
    // 操作前检查激活
    if (!_checkActivation()) return;
    await storage.save(_store);

    final views = ledgerViews();
    int nextIndex = 0;
    try {
      final s = license.safeStatus();
      if (s != null) nextIndex = s.stateIndex + 1;
    } catch (_) {}
    final payload = StateChainPayload.fromViews(views, stateIndex: nextIndex);
    final payloadJson = jsonEncode({
      ...payload.toJson(),
      'last_action': action,
      'last_action_meta': meta,
    });

    try {
      if (license.isActivated) {
        // 加密 payload 后写入 token
        final keyBytes = await storage.deviceKeyBytes();
        final encrypted = await PayloadCrypto.encryptWithDeviceKey(payloadJson, keyBytes);
        license.recordUsage(encrypted);
        if (_lastRawToken != null) {
          await license.backupRawTokenToDisk(_lastRawToken!);
        }
      }
    } catch (e) {
      debugPrint('recordUsage failed: $e');
    }
    // 更新同步时间戳
    _syncService?.lastUpdated = _latestUpdatedAt();
    notifyListeners();
  }

  // ============================================================
  // 导入 / 导出（加密）
  // ============================================================

  /// 导出全部数据为加密字符串（用户密码加密）
  Future<String> exportEncrypted(String passphrase) async {
    final plainJson = jsonEncode(_store.toJson());
    return PayloadCrypto.encryptWithPassphrase(plainJson, passphrase);
  }

  /// 从加密字符串导入数据（用户密码解密），覆盖当前数据
  Future<String?> importEncrypted(String cipherB64, String passphrase) async {
    try {
      final plainJson = await PayloadCrypto.decryptWithPassphrase(cipherB64, passphrase);
      final j = jsonDecode(plainJson) as Map<String, dynamic>;
      final imported = LocalLedgerStore.fromJson(j);
      // 覆盖：用导入的数据替换当前数据
      _store = imported;
      await storage.save(_store);
      notifyListeners();
      return null;
    } catch (e) {
      return '导入失败: $e';
    }
  }

  // ============================================================
  // 锁屏生命周期管理
  // ============================================================

  /// 应用进入后台时调用（记录时间戳）
  void onAppPaused() {
    if (screenLock.isEnabled && !_screenLocked) {
      _backgroundAt = DateTime.now();
    }
  }

  /// 应用回到前台时调用，超过超时则锁屏
  void onAppResumed() {
    if (!screenLock.isEnabled) return;
    if (_screenLocked) return;
    if (_backgroundAt == null) return;
    final elapsed = DateTime.now().difference(_backgroundAt!);
    if (elapsed >= _lockTimeout) {
      _screenLocked = true;
      notifyListeners();
    }
    _backgroundAt = null;
  }

  /// 解锁屏幕（验证通过后调用）
  void unlockScreen() {
    if (_screenLocked) {
      _screenLocked = false;
      _backgroundAt = null;
      notifyListeners();
    }
  }

  /// 手动锁屏
  void lockScreen() {
    if (screenLock.isEnabled && !_screenLocked) {
      _screenLocked = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _syncService?.stop();
    license.shutdown();
    super.dispose();
  }
}
