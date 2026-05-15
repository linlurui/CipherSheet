import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/cell.dart';
import '../../models/ledger.dart';
import '../../state/app_state.dart';
import 'widgets/batch_generate_dialog.dart';
import 'widgets/bill_cell.dart';
import 'widgets/settings_dialog.dart';

class LedgerDetailScreen extends StatefulWidget {
  final String ledgerId;
  const LedgerDetailScreen({super.key, required this.ledgerId});

  @override
  State<LedgerDetailScreen> createState() => _LedgerDetailScreenState();
}

class _LedgerDetailScreenState extends State<LedgerDetailScreen> {
  bool _ensuringDefaultBill = false;

  /// 确保账本至少有一个默认 Bill（无 Bill 时自动创建）
  Future<void> _ensureDefaultBill() async {
    if (_ensuringDefaultBill) return;
    _ensuringDefaultBill = true;
    try {
      final state = context.read<AppState>();
      final view = state.ledgerView(widget.ledgerId);
      if (view != null && view.bills.isEmpty) {
        await state.addBill(widget.ledgerId);
      }
    } finally {
      _ensuringDefaultBill = false;
    }
  }

  /// 点击单元格 → 弹框记账（可正可负，支持备注）
  Future<void> _onTapCell(Cell cell, Bill bill) async {
    final amountCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('记账 · ${cell.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'-?\d*\.?\d*')),
              ],
              decoration: const InputDecoration(
                labelText: '金额（正数收入，负数支出）',
                hintText: '如 100 或 -50',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarksCtrl,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '如：工资、餐饮、交通等',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final d = double.tryParse(amountCtrl.text);
                if (d != null) {
                  Navigator.pop(ctx, {'amount': d, 'remarks': remarksCtrl.text.trim()});
                }
              },
              child: const Text('确认')),
        ],
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    await context.read<AppState>().addCellRecord(
      widget.ledgerId, bill.billId, cell.cellId,
      amount: result['amount'] as double,
      remarks: result['remarks'] as String,
    );
  }

  /// 点击单元格内小图标 → 列出记账清单
  Future<void> _showCellRecords(Cell cell) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        final fmt = NumberFormat('#,##0.##');
        final timeFmt = DateFormat('MM-dd HH:mm');
        return AlertDialog(
          title: Text('${cell.title} · 记账清单'),
          content: SizedBox(
            width: 360,
            child: cell.records.isEmpty
                ? const Text('暂无记录')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: cell.records.length,
                    itemBuilder: (_, i) {
                      final r = cell.records[i];
                      return ListTile(
                        dense: true,
                        isThreeLine: false,
                        leading: Icon(
                          r.amount >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                          color: r.amount >= 0 ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        title: Text(
                          '${r.amount >= 0 ? "+" : ""}${fmt.format(r.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: r.amount >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                        subtitle: Text(
                          r.remarks.isNotEmpty
                              ? '${timeFmt.format(r.timestamp)}  ${r.remarks}'
                              : timeFmt.format(r.timestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭')),
          ],
        );
      },
    );
  }

  /// 单元格盘点：手动选择盈/平/亏，按对应公式计算
  Future<void> _markCellSettled(Cell cell, Bill bill) async {
    final state = context.read<AppState>();
    final view = state.ledgerView(widget.ledgerId);
    if (view == null) return;

    final formulas = view.ledger.formulas;

    // 盘盈、盘亏公式都未设置（且格子本身也没公式）则拦截
    final hasSurplus = (formulas[SettlementEvent.surplus]?.isNotEmpty ?? false) || cell.formula.isNotEmpty;
    final hasDeficit = (formulas[SettlementEvent.deficit]?.isNotEmpty ?? false) || cell.formula.isNotEmpty;
    if (!hasSurplus || !hasDeficit) {
      final missing = [
        if (!hasSurplus) '盘盈公式',
        if (!hasDeficit) '盘亏公式',
      ].join('、');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('请先设置公式'),
          content: Text('尚未设置 $missing，请在\n账本设置 → 盘点公式 中配置后再进行盘点。'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
      return;
    }

    final totalAmount = cell.totalAmount;

    // 弹出带 toggle 的盘点对话框
    final result = await showDialog<_SettleChoice>(
      context: context,
      builder: (ctx) => _SettleDialog(
        cell: cell,
        totalAmount: totalAmount,
        formulas: formulas,
      ),
    );
    if (result == null) return;
    if (!mounted) return;

    await context.read<AppState>().markCellSettled(
      widget.ledgerId, bill.billId, cell.cellId,
      event: result.event,
      amount: result.amount,
    );
  }

  /// 单元格参数设置：为账本定义的参数名设置数值
  Future<void> _openCellParams(Cell cell, Bill bill) async {
    final state = context.read<AppState>();
    final view = state.ledgerView(widget.ledgerId);
    if (view == null) return;
    final ledgerParams = view.ledger.parameters;
    if (ledgerParams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在账本设置中添加参数')),
      );
      return;
    }
    // 为每个账本参数准备 controller，初始值取 cell 已有的或 0
    final ctrls = <String, TextEditingController>{};
    for (final lp in ledgerParams) {
      final existing = cell.parameters.where((c) => c.key == lp.key);
      ctrls[lp.key] = TextEditingController(
        text: existing.isNotEmpty ? existing.first.value.toString() : '',
      );
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('参数 · ${cell.title}'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ledgerParams.map((lp) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextField(
                  controller: ctrls[lp.key],
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'-?\d*\.?\d*')),
                  ],
                  decoration: InputDecoration(
                    labelText: lp.key,
                    isDense: true,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    // 释放 controllers
    for (final c in ctrls.values) { c.dispose(); }
    if (result != true || !mounted) return;
    // 构建 cell parameters
    final newParams = <CellParameter>[];
    for (final lp in ledgerParams) {
      final v = double.tryParse(ctrls[lp.key]?.text ?? '') ?? 0;
      newParams.add(CellParameter(key: lp.key, value: v, unit: lp.unit));
    }
    await state.updateCellParameters(
      widget.ledgerId, bill.billId, cell.cellId,
      parameters: newParams,
    );
  }

  /// 已盘点单元格 → 点击结算图标输入结算金额
  Future<void> _openCellSettlement(Cell cell, Bill bill) async {
    final ctrl = TextEditingController(
        text: cell.settledAmount?.toStringAsFixed(2) ?? '');
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('结算 · ${cell.title} · ${cell.settlementEvent ?? ""}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'-?\d*\.?\d*')),
          ],
          decoration: const InputDecoration(labelText: '结算金额'),
          onSubmitted: (v) {
            final d = double.tryParse(v);
            if (d != null) Navigator.pop(ctx, d);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final d = double.tryParse(ctrl.text);
                if (d != null) Navigator.pop(ctx, d);
              },
              child: const Text('确认')),
        ],
      ),
    );
    if (amount == null) return;
    if (!mounted) return;
    await context.read<AppState>().setCellSettledAmount(
      widget.ledgerId, bill.billId, cell.cellId,
      amount: amount,
    );
  }

  Future<void> _onLongPressCell(Cell cell, Bill bill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${cell.title}？'),
        content: const Text('删除后无法恢复'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().deleteCell(widget.ledgerId, bill.billId, cell.cellId);
  }

  Bill? _defaultBill() {
    final view = context.read<AppState>().ledgerView(widget.ledgerId);
    if (view == null || view.bills.isEmpty) return null;
    return view.bills.first;
  }

  Future<void> _addCell() async {
    final state = context.read<AppState>();
    final bill = _defaultBill();
    if (bill == null) {
      await state.addBill(widget.ledgerId);
      final newBill = _defaultBill();
      if (newBill == null) return;
      await state.addCell(widget.ledgerId, newBill.billId);
      return;
    }
    await state.addCell(widget.ledgerId, bill.billId);
  }

  Future<void> _batchAddCells() async {
    final state = context.read<AppState>();
    final n = await showDialog<int>(
      context: context,
      builder: (_) => const BatchGenerateDialog(),
    );
    if (n == null || n <= 0) return;
    if (!mounted) return;
    var bill = _defaultBill();
    if (bill == null) {
      await state.addBill(widget.ledgerId);
      bill = _defaultBill();
      if (bill == null) return;
    }
    await state.batchAddCells(widget.ledgerId, bill.billId, n);
  }

  Future<void> _renameLedger(LedgerView view) async {
    final ctrl = TextEditingController(text: view.ledger.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名账本'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '账本名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == view.ledger.name) {
      return;
    }
    if (!mounted) return;
    await context.read<AppState>().renameLedger(widget.ledgerId, newName);
  }

  /// 导出数据（密码加密）
  Future<void> _exportData() async {
    final pwdCtrl = TextEditingController();
    final pwd2Ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置导出密码，导入时需要此密码解密', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '导出密码'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwd2Ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (pwdCtrl.text.isEmpty) return;
              if (pwdCtrl.text != pwd2Ctrl.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('两次密码不一致')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('导出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    final encrypted = await state.exportEncrypted(pwdCtrl.text);
    if (!mounted) return;
    // 用户选择保存路径
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出数据',
      fileName: 'ciphersheet_export_${DateTime.now().millisecondsSinceEpoch}.enc',
      type: FileType.any,
    );
    if (savePath == null) return;
    await File(savePath).writeAsString(encrypted);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导出到 $savePath')),
    );
  }

  /// 导入数据（密码解密）
  Future<void> _importData() async {
    // 选择文件
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择导出文件',
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.first;
    String cipherB64;
    if (pf.bytes != null) {
      cipherB64 = String.fromCharCodes(pf.bytes!);
    } else if (pf.path != null) {
      cipherB64 = await File(pf.path!).readAsString();
    } else {
      return;
    }
    final pwdCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据'),
        content: TextField(
          controller: pwdCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: '导入密码'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AppState>().importEncrypted(cipherB64.trim(), pwdCtrl.text);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入成功')),
      );
    }
  }

  Future<void> _batchSettle(Bill bill, LedgerView view) async {
    final formulas = view.ledger.formulas;
    final hasSurplus = formulas[SettlementEvent.surplus]?.isNotEmpty ?? false;
    final hasDeficit = formulas[SettlementEvent.deficit]?.isNotEmpty ?? false;
    if (!hasSurplus || !hasDeficit) {
      final missing = [
        if (!hasSurplus) '盘盈公式',
        if (!hasDeficit) '盘亏公式',
      ].join('、');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('请先设置公式'),
          content: Text('尚未设置 $missing，请在账本设置 → 盘点公式 中配置后再进行盘点。'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
        ),
      );
      return;
    }
    if (!mounted) return;
    final result = await showDialog<_BatchSettleResult>(
      context: context,
      builder: (_) => _BatchSettleDialog(
        bill: bill,
        formulas: formulas,
        defaultAction: view.ledger.rules.batchSettleDefault,
      ),
    );
    if (result == null || !mounted) return;
    final state = context.read<AppState>();
    for (final entry in result.choices.entries) {
      await state.markCellSettled(
        widget.ledgerId, bill.billId, entry.key,
        event: entry.value.event,
        amount: entry.value.amount,
      );
    }
  }

  Future<void> _openSettings(LedgerView view) async {
    await showDialog(
      context: context,
      builder: (_) => LedgerSettingsMenuDialog(
        ledger: view.ledger,
        onOpenParameters: () async {
          final r = await showDialog<List<LedgerParameter>>(
            context: context,
            builder: (_) => ParameterSettingsDialog(ledger: view.ledger),
          );
          if (r == null) return;
          if (!mounted) return;
          await context
              .read<AppState>()
              .updateLedgerParameters(widget.ledgerId, r);
        },
        onOpenFormula: () async {
          final r = await showDialog<Map<String, String>>(
            context: context,
            builder: (_) => FormulaSettingsDialog(ledger: view.ledger),
          );
          if (r == null) return;
          if (!mounted) return;
          await context
              .read<AppState>()
              .updateLedgerFormula(widget.ledgerId, r);
        },
        onOpenRules: () async {
          final r = await showDialog<LedgerRules>(
            context: context,
            builder: (_) => RulesSettingsDialog(rules: view.ledger.rules),
          );
          if (r == null) return;
          if (!mounted) return;
          await context
              .read<AppState>()
              .updateLedgerRules(widget.ledgerId, r);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final view = state.ledgerView(widget.ledgerId);
    if (view == null) {
      return const Scaffold(body: Center(child: Text('账本不存在')));
    }
    final locked = view.mnemonicEnabled && !state.isUnlocked;

    // 自动确保至少有一个默认 Bill
    if (view.bills.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureDefaultBill());
    }

    final bill = view.bills.isNotEmpty ? view.bills.first : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(view.ledger.name),
        actions: [
          if (view.ledger.rules.enableBatchSettle && bill != null)
            IconButton(
              tooltip: '一键盘点',
              icon: const Icon(Icons.playlist_add_check),
              onPressed: () => _batchSettle(bill!, view),
            ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(view),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (v) {
              switch (v) {
                case 'add_cell':
                  _addCell();
                  break;
                case 'batch_cells':
                  _batchAddCells();
                  break;
                case 'rename_ledger':
                  _renameLedger(view);
                  break;
                case 'export':
                  _exportData();
                  break;
                case 'import':
                  _importData();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'add_cell', child: Text('新增单元格')),
              const PopupMenuItem(value: 'batch_cells', child: Text('批量新增单元格')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'rename_ledger', child: Text('重命名账本')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'export', child: Text('导出数据')),
              const PopupMenuItem(value: 'import', child: Text('导入数据')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryCard(view: view, locked: locked),
          const SizedBox(height: 8),
          Expanded(
            child: bill == null
                ? const Center(child: CircularProgressIndicator())
                : _CellGrid(
                    bill: bill,
                    locked: locked,
                    interestRate: view.ledger.interestRate,
                    rules: view.ledger.rules,
                    onTap: (cell) => _onTapCell(cell, bill),
                    onLongPress: (cell) => _onLongPressCell(cell, bill),
                    onShowRecords: (cell) => _showCellRecords(cell),
                    onSettle: (cell) => _openCellSettlement(cell, bill!),
                    onMarkSettled: (cell) => _markCellSettled(cell, bill!),
                    onSetParams: (cell) => _openCellParams(cell, bill!),
                    onAdd: _addCell,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 总计卡片：总计/合计/盈亏 + 盘点状态汇总 + 账本参数
class _SummaryCard extends StatefulWidget {
  final LedgerView view;
  final bool locked;
  const _SummaryCard({required this.view, required this.locked});

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _expanded = false;

  LedgerView get view => widget.view;
  bool get locked => widget.locked;

  /// 计算汇总数据
  _SummaryData _calculateSummary() {
    // 汇总时用盘亏公式估算未盘点格子（兼容旧 'default' key）
    final ledgerFormula = view.ledger.formulas[SettlementEvent.deficit]
        ?? view.ledger.formulas['default'];
    int surplusCount = 0, deficitCount = 0, evenCount = 0, unsettledCount = 0;
    double totalAmount = 0;
    double totalCalculated = 0;

    for (final bill in view.bills) {
      for (final cell in bill.cells) {
        final cellTotal = cell.totalAmount;
        totalAmount += cellTotal;

        // 获取计算金额（已盘点用结算金额，未盘点用公式计算）
        double calculated;
        if (cell.settlementEvent != null && cell.settlementAmount != null) {
          calculated = cell.settlementAmount!;
        } else {
          calculated = cell.calculatedAmount(ledgerFormula: ledgerFormula);
        }
        totalCalculated += calculated;

        // 统计盘点状态
        if (cell.settlementEvent == null) {
          unsettledCount++;
        } else if (cell.settlementEvent == SettlementEvent.surplus) {
          surplusCount++;
        } else if (cell.settlementEvent == SettlementEvent.deficit) {
          deficitCount++;
        } else {
          evenCount++;
        }
      }
    }

    final profit = totalCalculated - totalAmount;

    return _SummaryData(
      totalAmount: totalAmount,
      combinedAmount: totalCalculated,
      profit: profit,
      surplusCount: surplusCount,
      deficitCount: deficitCount,
      evenCount: evenCount,
      unsettledCount: unsettledCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final data = locked ? null : _calculateSummary();
    final params = view.ledger.parameters;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 三列数据：总计/合计/盈亏，点击展开/收起盘点详情
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Expanded(
                  child: _AmountColumn(
                    label: '总计',
                    amount: data?.totalAmount,
                    locked: locked,
                    color: const Color(0xFF3563E9),
                  ),
                ),
                Container(height: 40, width: 1, color: Colors.black12),
                Expanded(
                  child: _AmountColumn(
                    label: '合计',
                    amount: data?.combinedAmount,
                    locked: locked,
                    color: Colors.black87,
                  ),
                ),
                Container(height: 40, width: 1, color: Colors.black12),
                Expanded(
                  child: _AmountColumn(
                    label: '盈亏',
                    amount: data?.profit,
                    locked: locked,
                    color: data?.profit != null && data!.profit >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    showSign: true,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.black38,
                ),
              ],
            ),
          ),
          // 可展开的盘点状态汇总
          if (_expanded && data != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatusBadge(label: '盘盈', count: data.surplusCount, color: Colors.green),
                _StatusBadge(label: '盘平', count: data.evenCount, color: Colors.blue),
                _StatusBadge(label: '盘亏', count: data.deficitCount, color: Colors.red),
                _StatusBadge(label: '未盘', count: data.unsettledCount, color: Colors.grey),
              ],
            ),
          ],
          if (params.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: params.map((p) => _ParamChip(parameter: p)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// 汇总数据
class _SummaryData {
  final double totalAmount;
  final double combinedAmount;
  final double profit;
  final int surplusCount;
  final int deficitCount;
  final int evenCount;
  final int unsettledCount;

  _SummaryData({
    required this.totalAmount,
    required this.combinedAmount,
    required this.profit,
    required this.surplusCount,
    required this.deficitCount,
    required this.evenCount,
    required this.unsettledCount,
  });
}

/// 金额列
class _AmountColumn extends StatelessWidget {
  final String label;
  final double? amount;
  final bool locked;
  final Color color;
  final bool showSign;

  const _AmountColumn({
    required this.label,
    required this.amount,
    required this.locked,
    required this.color,
    this.showSign = false,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          locked
              ? '••••'
              : (showSign && amount != null
                  ? '${amount! >= 0 ? '+' : ''}${fmt.format(amount!)}'
                  : fmt.format(amount ?? 0)),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 状态标签
class _StatusBadge extends StatelessWidget {
  final String label;
  final int count;
  final MaterialColor color;

  const _StatusBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.shade200),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color.shade700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: color.shade700)),
      ],
    );
  }
}

class _ParamChip extends StatelessWidget {
  final LedgerParameter parameter;
  const _ParamChip({required this.parameter});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${parameter.key}：',
            style: const TextStyle(color: Colors.black54)),
        Text(
          '${fmt.format(parameter.value)}${parameter.unit}',
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: Colors.black87),
        ),
      ],
    );
  }
}

class _CellGrid extends StatelessWidget {
  final Bill bill;
  final bool locked;
  final double interestRate;
  final LedgerRules rules;
  final void Function(Cell) onTap;
  final void Function(Cell) onLongPress;
  final void Function(Cell) onShowRecords;
  final void Function(Cell) onSettle;
  final void Function(Cell) onMarkSettled;
  final void Function(Cell) onSetParams;
  final VoidCallback onAdd;
  const _CellGrid({
    required this.bill,
    required this.locked,
    required this.interestRate,
    required this.rules,
    required this.onTap,
    required this.onLongPress,
    required this.onShowRecords,
    required this.onSettle,
    required this.onMarkSettled,
    required this.onSetParams,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cells = bill.sortedCells;
    if (cells.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_outlined,
                size: 64, color: Colors.black26),
            const SizedBox(height: 8),
            const Text('暂无记账单元',
                style: TextStyle(color: Colors.black45)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增格子'),
            ),
          ],
        ),
      );
    }
    final width = MediaQuery.of(context).size.width;
    int crossAxisCount;
    if (width >= 1200) {
      crossAxisCount = 8;
    } else if (width >= 900) {
      crossAxisCount = 6;
    } else if (width >= 600) {
      crossAxisCount = 5;
    } else if (width >= 380) {
      crossAxisCount = 4;
    } else {
      crossAxisCount = 3;
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 140,
      ),
      itemCount: cells.length,
      itemBuilder: (ctx, i) {
        final c = cells[i];
        return BillCell(
          cell: c,
          locked: locked,
          interestRate: interestRate,
          onTap: () => onTap(c),
          onLongPress: () => onLongPress(c),
          onShowRecords: () => onShowRecords(c),
          onDelete: () => onLongPress(c),
          // 结算图标：disableSettle=true 时隐藏
          onSettle: (!rules.disableSettle && c.settlementEvent != null)
              ? () => onSettle(c)
              : null,
          // 盘点图标：enableBatchSettle=true 时格子内隐藏（用一键盘点代替）
          onMarkSettled: rules.enableBatchSettle ? null : () => onMarkSettled(c),
          // 参数图标：enableCellParams=false 时隐藏
          onSetParams: rules.enableCellParams ? () => onSetParams(c) : null,
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 盘点结果数据
// ──────────────────────────────────────────────────────────────
class _SettleChoice {
  final String event;
  final double amount;
  const _SettleChoice({required this.event, required this.amount});
}

// ──────────────────────────────────────────────────────────────
// 盘点弹框：盈/平/亏 toggle + 公式实时预览
// ──────────────────────────────────────────────────────────────
class _SettleDialog extends StatefulWidget {
  final Cell cell;
  final double totalAmount;
  final Map<String, String> formulas;

  const _SettleDialog({
    required this.cell,
    required this.totalAmount,
    required this.formulas,
  });

  @override
  State<_SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends State<_SettleDialog> {
  String _selected = SettlementEvent.deficit;

  double _compute(String event) {
    if (event == SettlementEvent.even) return widget.totalAmount;
    final formulaKey = event; // '盘盈' or '盘亏'
    // 优先单元格自己的公式，其次账本公式
    final f = widget.cell.formula.isNotEmpty
        ? widget.cell.formula
        : (widget.formulas[formulaKey] ?? '');
    if (f.isEmpty) return widget.totalAmount;
    return widget.cell.calculatedAmount(ledgerFormula: f);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final amount = _compute(_selected);

    final Color activeColor = _selected == SettlementEvent.surplus
        ? Colors.green.shade700
        : _selected == SettlementEvent.deficit
            ? Colors.red.shade700
            : Colors.blue.shade700;

    Widget toggleBtn(String event, String label, Color color) {
      final active = _selected == event;
      return GestureDetector(
        onTap: () => setState(() => _selected = event),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? color : Colors.grey.shade300, width: 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.black54,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text('盘点 · ${widget.cell.title}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 记账金额
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('记账金额', style: TextStyle(color: Colors.black54, fontSize: 13)),
                Text(fmt.format(widget.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 16),
            // 盈/平/亏 toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                toggleBtn(SettlementEvent.surplus, '盘盈', Colors.green.shade600),
                toggleBtn(SettlementEvent.even,    '盘平', Colors.blue.shade600),
                toggleBtn(SettlementEvent.deficit, '盘亏', Colors.red.shade600),
              ],
            ),
            const SizedBox(height: 20),
            // 公式计算结果
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: activeColor.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: activeColor.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    _selected == SettlementEvent.even ? '持平' :
                    _selected == SettlementEvent.surplus ? '应收' : '应付',
                    style: TextStyle(fontSize: 12, color: activeColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fmt.format(amount),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: activeColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: activeColor),
          onPressed: () => Navigator.pop(
            context,
            _SettleChoice(event: _selected, amount: amount),
          ),
          child: const Text('确认盘点'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 一键盘点结果
// ──────────────────────────────────────────────────────────────
class _BatchSettleResult {
  /// cellId -> _SettleChoice
  final Map<String, _SettleChoice> choices;
  const _BatchSettleResult(this.choices);
}

// ──────────────────────────────────────────────────────────────
// 一键盘点弹框
// ──────────────────────────────────────────────────────────────
class _BatchSettleDialog extends StatefulWidget {
  final Bill bill;
  final Map<String, String> formulas;
  final String defaultAction; // DefaultSettleAction

  const _BatchSettleDialog({
    required this.bill,
    required this.formulas,
    required this.defaultAction,
  });

  @override
  State<_BatchSettleDialog> createState() => _BatchSettleDialogState();
}

class _BatchSettleDialogState extends State<_BatchSettleDialog> {
  final Set<String> _selected = {};
  String _event = SettlementEvent.deficit;

  double _compute(Cell cell, String event) {
    if (event == SettlementEvent.even) return cell.totalAmount;
    final f = cell.formula.isNotEmpty
        ? cell.formula
        : (widget.formulas[event] ?? '');
    if (f.isEmpty) return cell.totalAmount;
    return cell.calculatedAmount(ledgerFormula: f);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final cells = widget.bill.sortedCells.where((c) => c.totalAmount != 0).toList();

    Color eventColor(String e) => e == SettlementEvent.surplus
        ? Colors.green.shade600
        : e == SettlementEvent.deficit
            ? Colors.red.shade600
            : Colors.blue.shade600;

    Widget toggleBtn(String event, String label) {
      final active = _event == event;
      final color = eventColor(event);
      return GestureDetector(
        onTap: () => setState(() => _event = event),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? color : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                color: active ? Colors.white : Colors.black54,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              )),
        ),
      );
    }

    return AlertDialog(
      title: const Text('一键盘点'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 盈/平/亏 toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                toggleBtn(SettlementEvent.surplus, '盘盈'),
                toggleBtn(SettlementEvent.even,    '盘平'),
                toggleBtn(SettlementEvent.deficit, '盘亏'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '未选中单元格默认处理：${widget.defaultAction}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // 格子列表（可滚动多选）
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cells.length,
                itemBuilder: (_, i) {
                  final c = cells[i];
                  final checked = _selected.contains(c.cellId);
                  final previewEvent = checked ? _event : widget.defaultAction;
                  final previewAmount = previewEvent == DefaultSettleAction.none
                      ? null
                      : _compute(c, previewEvent);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    onChanged: (_) => setState(() {
                      if (checked) {
                        _selected.remove(c.cellId);
                      } else {
                        _selected.add(c.cellId);
                      }
                    }),
                    title: Text(c.title,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Row(
                      children: [
                        Text('记账：${fmt.format(c.totalAmount)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        if (previewAmount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '→ $previewEvent ${fmt.format(previewAmount)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: eventColor(previewEvent),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else if (previewEvent == DefaultSettleAction.none) ...[
                          const SizedBox(width: 8),
                          const Text('→ 不处理',
                              style: TextStyle(fontSize: 11, color: Colors.black26)),
                        ],
                      ],
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            // 全选/取消全选
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == cells.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(cells.map((c) => c.cellId));
                    }
                  }),
                  child: Text(_selected.length == cells.length ? '取消全选' : '全选'),
                ),
                const Spacer(),
                Text('已选 ${_selected.length}/${cells.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final choices = <String, _SettleChoice>{};
            for (final c in cells) {
              String effectiveEvent;
              if (_selected.contains(c.cellId)) {
                effectiveEvent = _event;
              } else {
                // 默认处理
                if (widget.defaultAction == DefaultSettleAction.none) continue;
                effectiveEvent = widget.defaultAction;
              }
              choices[c.cellId] = _SettleChoice(
                event: effectiveEvent,
                amount: _compute(c, effectiveEvent),
              );
            }
            Navigator.pop(context, _BatchSettleResult(choices));
          },
          child: const Text('确认盘点'),
        ),
      ],
    );
  }
}
