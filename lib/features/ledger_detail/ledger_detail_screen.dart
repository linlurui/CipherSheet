import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/bill.dart';
import '../../models/cell.dart';
import '../../models/ledger.dart';
import '../../state/app_state.dart';
import 'widgets/batch_generate_dialog.dart';
import 'widgets/bill_cell.dart';
import 'widgets/cell_detail_screen.dart';
import 'widgets/settings_dialog.dart';

class LedgerDetailScreen extends StatefulWidget {
  final String ledgerId;
  const LedgerDetailScreen({super.key, required this.ledgerId});

  @override
  State<LedgerDetailScreen> createState() => _LedgerDetailScreenState();
}

class _LedgerDetailScreenState extends State<LedgerDetailScreen> {
  static String? _lastExportDir;
  bool _ensuringDefaultBill = false;
  String _cellFilter = '';
  final _searchCtrl = TextEditingController();
  final _gridScrollCtrl = ScrollController();
  _PredictionData? _prediction;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _gridScrollCtrl.dispose();
    super.dispose();
  }

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
        final screenWidth = MediaQuery.of(context).size.width;
        final contentWidth = screenWidth > 500 ? 360.0 : screenWidth * 0.85;
        return AlertDialog(
          title: Text('${cell.title} · 记账清单'),
          content: SizedBox(
            width: contentWidth,
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

    // 记账金额为0的格子不用盘点
    if (cell.totalAmount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记账金额为0，无需盘点')),
        );
      }
      return;
    }

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
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final contentWidth = screenWidth > 500 ? 320.0 : screenWidth * 0.85;
        return AlertDialog(
        title: Text('参数 · ${cell.title}'),
        content: SizedBox(
          width: contentWidth,
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
      );
      },
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
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.label_outline, color: Colors.orange),
              title: const Text('设置标签'),
              onTap: () => Navigator.pop(ctx, 'tag'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text('删除 ${cell.title}', style: TextStyle(color: Colors.red.shade400)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'tag') {
      await _showTagsDialog(cell, bill);
    } else if (action == 'delete') {
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
  }

  Future<void> _showTagsDialog(Cell cell, Bill bill) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(
          text: cell.tags.isNotEmpty ? cell.tags.first : '',
        );
        return AlertDialog(
          title: Text('格子 ${cell.title} 标签'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入标签名，留空则清除标签',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (tag == null || !mounted) return;
    final newTags = tag.isEmpty ? <String>[] : [tag];
    await context.read<AppState>().updateCell(
      widget.ledgerId, bill.billId,
      cell.copyWith(tags: newTags),
    );
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
    } else {
      await state.addCell(widget.ledgerId, bill.billId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新增单元格成功'), duration: Duration(seconds: 1)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gridScrollCtrl.hasClients) {
        _gridScrollCtrl.animateTo(
          _gridScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('成功新增 $n 个单元格'), duration: const Duration(seconds: 1)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gridScrollCtrl.hasClients) {
        _gridScrollCtrl.animateTo(
          _gridScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
    final fileName = 'ciphersheet_export_${DateTime.now().millisecondsSinceEpoch}.enc';
    String? savePath;
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动端：写到临时目录，弹系统分享面板，用户自己决定存哪
      final dir = await getTemporaryDirectory();
      final tmpPath = '${dir.path}/$fileName';
      await File(tmpPath).writeAsString(encrypted);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(tmpPath, mimeType: 'application/octet-stream')],
        subject: 'CipherSheet 数据导出',
      );
      return;
    } else {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出数据',
        fileName: fileName,
        type: FileType.any,
      );
      if (savePath == null) return;
      _lastExportDir = p.dirname(savePath);
      await File(savePath).writeAsString(encrypted);
    }
    if (!mounted) return;
    final hint = '已导出到 $savePath';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hint),
        duration: const Duration(seconds: 30),
        action: SnackBarAction(label: '关闭', onPressed: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }),
      ),
    );
  }

  /// 导入数据（密码解密）
  Future<void> _importData() async {
    // 选择文件，优先在上次导出目录打开
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择导出文件',
      type: FileType.any,
      initialDirectory: _lastExportDir,
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

  /// 撤销记账：自动定位最近一条记账记录，一步确认即撤销
  Future<void> _undoLastRecord(LedgerView view) async {
    // 收集所有格子的记录
    final entries = <_RecordEntry>[];
    for (final bill in view.bills) {
      for (final cell in bill.cells) {
        for (final record in cell.records) {
          entries.add(_RecordEntry(bill: bill, cell: cell, record: record));
        }
      }
    }

    if (!mounted) return;

    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前账本暂无记账记录')),
      );
      return;
    }

    // 找出创建时间最新的那条
    entries.sort((a, b) => b.record.createdAt.compareTo(a.record.createdAt));
    final latest = entries.first;
    final fmt = NumberFormat('#,##0.##');
    final dateFmt = DateFormat('MM-dd HH:mm:ss');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销最近一笔记账'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将撤销以下记账记录：',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF3563E9).withValues(alpha: 0.12),
                    child: Text(latest.cell.title,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF3563E9))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmt.format(latest.record.amount),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(
                          latest.record.remarks.isEmpty
                              ? dateFmt.format(latest.record.createdAt)
                              : '${latest.record.remarks}  ·  ${dateFmt.format(latest.record.createdAt)}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    await context.read<AppState>().deleteCellRecord(
      widget.ledgerId,
      latest.bill.billId,
      latest.cell.cellId,
      latest.record.recordId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已撤销格子「${latest.cell.title}」的记账记录')),
      );
    }
  }

  /// 一键清零：清除该账本的所有记账记录、盘点记录、结算记录
  Future<void> _clearAllData(LedgerView view) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认一键清零？'),
        content: const Text(
          '此操作将清除该账本的所有：\n'
          '· 记账记录（所有单元格的进出明细）\n'
          '· 盘点记录（所有结算事件）\n'
          '· 结算历史\n\n'
          '此操作不可恢复，请确认已备份重要数据。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清零'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final state = context.read<AppState>();

    // 如果关闭了单元参数设置，清零同时重置所有单元格的 parameters 和 multiplier 到账本默认
    final disableCellParams = !view.ledger.rules.enableCellParams;
    final defaultParams = view.ledger.parameters
        .map((p) => CellParameter(key: p.key, value: p.value, unit: p.unit))
        .toList();

    // 清除所有单元格的 records 和盘点/结算状态
    // 关闭单元参数时：同步重置 parameters + multiplier 至默认值（确保所有格子显示相同颜色/参数）
    for (final bill in view.bills) {
      for (final cell in bill.cells) {
        final needsParamReset = disableCellParams &&
            (cell.multiplier != 1.0 ||
                cell.parameters.map((p) => '${p.key}:${p.value}').join(',') !=
                    defaultParams.map((p) => '${p.key}:${p.value}').join(','));
        if (cell.records.isNotEmpty || cell.settlementEvent != null || needsParamReset) {
          await state.updateCell(
            widget.ledgerId,
            bill.billId,
            cell.copyWith(
              records: [],
              clearSettlement: true,
              multiplier: disableCellParams ? 1.0 : null,
              parameters: disableCellParams
                  ? defaultParams.map((p) => CellParameter(key: p.key, value: p.value, unit: p.unit)).toList()
                  : null,
            ),
          );
        }
      }
    }
    // 清除结算历史
    await state.clearLedgerSettlements(widget.ledgerId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清零完成')),
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

  /// 计算盘点预测：
  ///   盘盈预测 = 所有格子盘盈之和（含触发格，已记账=已收钱）
  ///   盘亏预测 = 触发格盘亏结果（负值，需赔付）
  ///   盈亏预测 = 盘盈预测 + 盘亏预测
  _PredictionData? _calculatePrediction(Cell triggerCell, LedgerView view) {
    final formulas = view.ledger.formulas;
    final surplusF = formulas[SettlementEvent.surplus] ?? '';
    final deficitF = formulas[SettlementEvent.deficit] ?? '';

    // 所有格子盘盈之和（含触发格，因为已记账说明已收钱）
    double surplusTotal = 0;
    for (final bill in view.bills) {
      for (final cell in bill.cells) {
        final s = surplusF.isEmpty
            ? cell.totalAmount * cell.multiplier
            : cell.calculatedAmount(ledgerFormula: surplusF);
        surplusTotal += s;
      }
    }

    // 触发格盘亏结果（赔付额，取负值）
    final deficitPayout = deficitF.isEmpty
        ? triggerCell.totalAmount * triggerCell.multiplier
        : triggerCell.calculatedAmount(ledgerFormula: deficitF).abs();
    final deficitCalc = -deficitPayout;

    // 盈亏预测 = 其余盘盈 + 触发格盘亏
    final profit = surplusTotal + deficitCalc;

    return _PredictionData(
      cellTitle: triggerCell.title,
      surplusAmount: surplusTotal,
      deficitAmount: deficitCalc,
      totalAmount: triggerCell.totalAmount,
      profit: profit,
    );
  }

  /// 点击单元格预测图标：对该格子单独预测盘盈/盘亏两种情形
  void _onPredictCell(Cell cell, Bill bill, LedgerView view) {
    setState(() {
      _prediction = _calculatePrediction(cell, view);
    });
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

  /// 处理快捷记账菜单
  Future<void> _handleQuickAdd(String type, Bill bill, LedgerView view) async {
    switch (type) {
      case 'quick':
        // 快捷记账：序号+金额两个输入框
        await _showQuickAddDialog(bill, view);
        break;
      case 'batch':
        // 批量记账：多选单元格+统一金额
        await _showBatchAddDialog(bill, view);
        break;
      case 'tag':
        // 标签记账 - 弹出选择单元格并添加标签
        await _showTagAddDialog(bill, view);
        break;
      case 'smart':
        // 智能记账
        await _showSmartAddDialog(bill, view);
        break;
    }
  }

  /// 快捷记账对话框：序号 + 金额
  Future<void> _showQuickAddDialog(Bill bill, LedgerView view) async {
    final indexCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('快捷记账'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: indexCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '序号',
                      hintText: '如: 01',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                    decoration: const InputDecoration(
                      labelText: '金额',
                      hintText: '如: 100',
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      final index = int.tryParse(indexCtrl.text);
                      final amount = double.tryParse(amountCtrl.text);
                      if (index != null && amount != null) Navigator.pop(ctx, true);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final index = int.tryParse(indexCtrl.text);
              final amount = double.tryParse(amountCtrl.text);
              if (index != null && amount != null) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final index = int.tryParse(indexCtrl.text);
    final amount = double.tryParse(amountCtrl.text);
    if (index == null || amount == null) return;

    // 查找对应序号的单元格
    final targetCell = bill.cells.firstWhere(
      (c) => c.orderIndex == index,
      orElse: () => bill.cells.first,
    );
    if (targetCell.orderIndex != index) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未找到序号为 $index 的单元格')),
        );
      }
      return;
    }

    await context.read<AppState>().addCellRecord(
      widget.ledgerId, bill.billId, targetCell.cellId,
      amount: amount,
      remarks: '快捷记账',
    );
  }

  /// 批量记账对话框：多选单元格 + 统一金额
  Future<void> _showBatchAddDialog(Bill bill, LedgerView view) async {
    final result = await showDialog<_BatchAddResult?>(
      context: context,
      builder: (ctx) => _BatchAddDialog(cells: bill.cells),
    );

    if (result == null || !mounted) return;

    final state = context.read<AppState>();
    for (final cellId in result.selectedCellIds) {
      await state.addCellRecord(
        widget.ledgerId, bill.billId, cellId,
        amount: result.amount,
        remarks: '批量记账',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记账 ${result.selectedCellIds.length} 个单元格')),
      );
    }
  }

  /// 标签记账对话框：多选标签 + 输入金额 → 一键记账
  Future<void> _showTagAddDialog(Bill bill, LedgerView view) async {
    final allTags = <String>{for (var c in bill.cells) ...c.tags}.toList()..sort();

    if (allTags.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前账本没有标签，请先给单元格添加标签')),
        );
      }
      return;
    }

    final result = await showDialog<_TagAddResult>(
      context: context,
      builder: (ctx) => _TagAddDialog(allTags: allTags, bill: bill),
    );

    if (result == null || !mounted) return;

    final state = context.read<AppState>();
    final targetCells = bill.cells
        .where((c) => c.tags.any((t) => result.selectedTags.contains(t)))
        .toList();

    for (final cell in targetCells) {
      await state.addCellRecord(
        widget.ledgerId, bill.billId, cell.cellId,
        amount: result.amount,
        remarks: '标签记账: ${result.selectedTags.join('/')}',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已为 ${targetCells.length} 个单元格记账')),
      );
    }
  }

  /// 智能记账对话框
  Future<void> _showSmartAddDialog(Bill bill, LedgerView view) async {
    final textCtrl = TextEditingController();
    final result = await showDialog<_SmartAddResult?>(
      context: context,
      builder: (ctx) => _SmartAddDialog(
        cells: bill.cells,
        onPreview: (text) => _parseSmartAddText(text, bill.cells),
      ),
    );
    if (result == null || !mounted) return;

    // 应用记账结果
    final state = context.read<AppState>();
    for (final rec in result.records) {
      if (rec.amount != 0) {
        await state.addCellRecord(
          widget.ledgerId, bill.billId, rec.cellId,
          amount: rec.amount,
          remarks: '智能记账',
        );
      }
    }
  }

  /// 解析智能记账文本，返回列表（允许同一格多条，用于重复检测）
  /// 支持格式：
  /// - "11.47.各20" / "5，34，各15元" / "5 34 各15" → 各格子=指定金额
  /// - "36号20元" / "36号 20" → 36号=20
  /// - "22号40元，4号5元"
  List<_ParsedRecord> _parseSmartAddText(String text, List<Cell> cells) {
    final result = <_ParsedRecord>[];
    final cellMap = {for (var c in cells) c.title: c.cellId};

    // 按句子终止符分段（。！；换行），保留各段独立解析避免跨段误匹配
    final segments = text
        .split(RegExp(r'[。！；\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final segment in segments) {
      var remaining = segment;

      // ── 步骤1：提取 "N(分隔符)N...各/每X" 格式 ──
      // 分隔符允许：. ， , 、空格（不跨越中文标点句号）
      final eachRe = RegExp(r'((?:\d+[.,，、\s]+)+)(?:各|每)(\d+(?:\.\d+)?)元?');
      for (final m in eachRe.allMatches(segment)) {
        final amount = double.tryParse(m.group(2)!) ?? 0;
        for (final n in RegExp(r'\d+').allMatches(m.group(1)!)) {
          final title = n.group(0)!.padLeft(2, '0');
          if (cellMap.containsKey(title)) {
            result.add(_ParsedRecord(cellMap[title]!, amount));
          }
        }
      }
      remaining = remaining.replaceAll(eachRe, '');

      // ── 步骤2：提取 "N号[分隔]X元" 格式 ──
      final numRe = RegExp(r'(\d{1,3})号[，,\s]*(\d+(?:\.\d+)?)元?');
      for (final m in numRe.allMatches(remaining)) {
        final title = m.group(1)!.padLeft(2, '0');
        final amount = double.tryParse(m.group(2)!) ?? 0;
        if (cellMap.containsKey(title)) {
          result.add(_ParsedRecord(cellMap[title]!, amount));
        }
      }
      remaining = remaining.replaceAll(numRe, '');

      // ── 步骤3：剩余 "N X" 简单配对（N是有效格子编号）──
      final simpleRe = RegExp(r'\b(\d{1,3})\s+(\d+(?:\.\d+)?)\s*元?');
      for (final m in simpleRe.allMatches(remaining)) {
        final title = m.group(1)!.padLeft(2, '0');
        final amount = double.tryParse(m.group(2)!) ?? 0;
        if (cellMap.containsKey(title)) {
          result.add(_ParsedRecord(cellMap[title]!, amount));
        }
      }
    }

    return result;
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
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            return Row(
              children: [
                // 账本名称（使用 Flexible 防止溢出）
                Flexible(
                  child: Text(
                    view.ledger.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 搜索框（宽屏显示，窄屏点击搜索图标展开）
                if (isWide)
                  SizedBox(
                    width: 120,
                    height: 36,
                    child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: '搜索单元格...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _cellFilter = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        onChanged: (v) => setState(() => _cellFilter = v),
                      ),
                    )
                else
                  // 窄屏：搜索图标点击展开
                  IconButton(
                    icon: const Icon(Icons.search, size: 20),
                    onPressed: () {
                      showSearch(
                        context: context,
                        delegate: _CellSearchDelegate(
                          cells: bill?.cells ?? [],
                          onSelected: (cell) {
                            _cellFilter = cell.title;
                            _searchCtrl.text = cell.title;
                            setState(() {});
                          },
                        ),
                      );
                    },
                  ),
                // 窄屏：使用 Wrap 防止溢出
                if (!isWide && bill != null)
                  Wrap(
                    spacing: 4,
                    children: [
                      if (view.ledger.rules.enableBatchSettle)
                        IconButton(
                          tooltip: '一键盘点',
                          icon: const Icon(Icons.playlist_add_check, size: 20),
                          onPressed: () => _batchSettle(bill, view),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        tooltip: '快捷记账',
                        onSelected: (type) => _handleQuickAdd(type, bill, view),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'quick', child: Text('快捷记账')),
                          const PopupMenuItem(value: 'batch', child: Text('批量记账')),
                          const PopupMenuItem(value: 'tag', child: Text('标签记账')),
                          const PopupMenuItem(value: 'smart', child: Text('智能记账')),
                        ],
                      ),
                    ],
                  ),
                // 宽屏：直接显示按钮
                if (isWide) ...[
                  const SizedBox(width: 8),
                  if (bill != null && view.ledger.rules.enableBatchSettle)
                    IconButton(
                      tooltip: '一键盘点',
                      icon: const Icon(Icons.playlist_add_check, size: 20),
                      onPressed: () => _batchSettle(bill, view),
                    ),
                  if (bill != null)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: '快捷记账',
                      onSelected: (type) => _handleQuickAdd(type, bill, view),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'quick', child: Text('快捷记账')),
                        const PopupMenuItem(value: 'batch', child: Text('批量记账')),
                        const PopupMenuItem(value: 'tag', child: Text('标签记账')),
                        const PopupMenuItem(value: 'smart', child: Text('智能记账')),
                      ],
                    ),
                ],
              ],
            );
          },
        ),
        actions: [
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
                case 'clear_all':
                  _clearAllData(view);
                  break;
                case 'undo_record':
                  _undoLastRecord(view);
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
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'undo_record',
                child: Row(
                  children: [
                    Icon(Icons.undo, size: 18, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('撤销记账'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'clear_all',
                child: Text('一键清零', style: TextStyle(color: Colors.red.shade400)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryCard(
            view: view,
            bill: bill,
            locked: locked,
            prediction: _prediction,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: bill == null
                ? const Center(child: CircularProgressIndicator())
                : _CellGrid(
                    bill: bill,
                    filter: _cellFilter,
                    locked: locked,
                    scrollController: _gridScrollCtrl,
                    interestRate: view.ledger.interestRate,
                    rules: view.ledger.rules,
                    onTap: (cell) => _onTapCell(cell, bill),
                    onLongPress: (cell) => _onLongPressCell(cell, bill),
                    onShowRecords: (cell) => _showCellRecords(cell),
                    onSettle: (cell) => _openCellSettlement(cell, bill!),
                    onMarkSettled: (cell) => _markCellSettled(cell, bill!),
                    onSetParams: (cell) => _openCellParams(cell, bill!),
                    onPredict: (cell) => _onPredictCell(cell, bill, view),
                    onAdd: _addCell,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 总计卡片：总计/合计/盈亏 + 搜索过滤 + 盘点预测
class _SummaryCard extends StatefulWidget {
  final LedgerView view;
  final Bill? bill;
  final bool locked;
  final _PredictionData? prediction;

  const _SummaryCard({
    required this.view,
    this.bill,
    required this.locked,
    this.prediction,
  });

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _expanded = false;

  LedgerView get view => widget.view;
  bool get locked => widget.locked;

  @override
  void didUpdateWidget(_SummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 有新预测数据时自动展开
    if (widget.prediction != null && widget.prediction != oldWidget.prediction) {
      setState(() => _expanded = true);
    }
  }


  /// 计算汇总数据
  _SummaryData _calculateSummary() {
    final cells = _getFilteredCells();
    int surplusCount = 0, deficitCount = 0, evenCount = 0, unsettledCount = 0;
    double totalAmount = 0;
    double totalCalculated = 0;
    double settledInputTotal = 0; // 已盘点格子的原始金额，用于计算盈亏

    for (final cell in cells) {
      final cellTotal = cell.totalAmount;
      totalAmount += cellTotal;

      // 获取计算金额（已盘点用结算金额，未盘点不计入合计）
      if (cell.settlementEvent != null && cell.settlementAmount != null) {
        totalCalculated += cell.settlementAmount!;
        settledInputTotal += cellTotal;
      }

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

    // 盈亏只统计已盘点格子（未盘点时为 0，避免误导）
    final profit = totalCalculated - settledInputTotal;

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

  List<Cell> _getFilteredCells() {
    // 从 view 获取所有 cells（不过滤，保持统计完整性）
    final List<Cell> cells = [];
    for (final bill in view.bills) {
      cells.addAll(bill.cells);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final data = locked ? null : _calculateSummary();
    final pred = widget.prediction;

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
          // 三列数据：总计/合计/盈亏（点击展开/收起预测）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: pred != null ? () => setState(() => _expanded = !_expanded) : null,
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
                if (pred != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Colors.black38,
                    ),
                  ),
              ],
            ),
          ),
          // 盘点预测区域：有数据且展开时显示
          if (pred != null && _expanded) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              '盘点预测',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _PredictionBadge(
                  label: '盘盈预测',
                  amount: pred.surplusAmount,
                  color: Colors.green,
                  locked: locked,
                ),
                _PredictionBadge(
                  label: '盘亏预测',
                  amount: pred.deficitAmount,
                  color: Colors.red,
                  locked: locked,
                ),
                _PredictionBadge(
                  label: '盈亏预测',
                  amount: pred.profit,
                  color: Colors.blue,
                  locked: locked,
                ),
              ],
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

// ──────────────────────────────────────────────────────────────
// 单元格搜索委托（移动端搜索界面）
class _CellSearchDelegate extends SearchDelegate<Cell> {
  final List<Cell> cells;
  final void Function(Cell) onSelected;

  _CellSearchDelegate({
    required this.cells,
    required this.onSelected,
  });

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () => query = '',
    ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, cells.first),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final filtered = query.isEmpty
        ? cells
        : cells.where((c) => c.title.toLowerCase().contains(query.toLowerCase())).toList();

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final c = filtered[i];
        return ListTile(
          title: Text(c.title),
          subtitle: Text('记账: ${c.totalAmount.toStringAsFixed(2)}'),
          onTap: () {
            onSelected(c);
            close(context, c);
          },
        );
      },
    );
  }
}

/// 预测数据（单格预测：盘盈/盘亏两种情形下的结算值）
class _PredictionData {
  final String cellTitle;       // 被预测的格子编号
  final double surplusAmount;   // 若盘盈：应收/应付金额
  final double deficitAmount;   // 若盘亏：应收/应付金额（负值）
  final double totalAmount;     // 格子当前合计金额
  final double profit;          // 盘盈情形下的净盈亏 = surplusAmount - totalAmount

  _PredictionData({
    required this.cellTitle,
    required this.surplusAmount,
    required this.deficitAmount,
    required this.totalAmount,
    required this.profit,
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
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

/// 预测金额标签（显示金额而非计数）
class _PredictionBadge extends StatelessWidget {
  final String label;
  final double? amount;
  final MaterialColor color;
  final bool locked;

  const _PredictionBadge({
    required this.label,
    this.amount,
    required this.color,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
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
            locked
                ? '••••'
                : (amount != null
                    ? '${amount! > 0 ? "+" : ""}${fmt.format(amount!)}'
                    : '-'),
            style: TextStyle(
              fontSize: 13,
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
  final String filter;
  final bool locked;
  final double interestRate;
  final LedgerRules rules;
  final ScrollController? scrollController;
  final void Function(Cell) onTap;
  final void Function(Cell) onLongPress;
  final void Function(Cell) onShowRecords;
  final void Function(Cell) onSettle;
  final void Function(Cell) onMarkSettled;
  final void Function(Cell) onSetParams;
  final void Function(Cell)? onPredict;
  final VoidCallback onAdd;
  const _CellGrid({
    required this.bill,
    this.filter = '',
    required this.locked,
    required this.interestRate,
    required this.rules,
    this.scrollController,
    required this.onTap,
    required this.onLongPress,
    required this.onShowRecords,
    required this.onSettle,
    required this.onMarkSettled,
    required this.onSetParams,
    this.onPredict,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final filterLower = filter.trim().toLowerCase();
    final cells = bill.sortedCells.where((c) {
      if (filterLower.isEmpty) return true;
      return c.title.toLowerCase().contains(filterLower);
    }).toList();
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
    // 根据格子中最多参数数量动态计算行高：基础高度 + 每个参数约 14px
    final maxParams = cells.fold<int>(0, (m, c) => c.parameters.length > m ? c.parameters.length : m);
    final mainAxisExtent = 130.0 + maxParams * 14.0;
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: cells.length,
      itemBuilder: (ctx, i) {
        final c = cells[i];
        return BillCell(
          key: ValueKey(c.cellId),
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
          // 预测图标
          onPredict: onPredict != null ? () => onPredict!(c) : null,
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

    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 500 ? 320.0 : screenWidth * 0.85;

    return AlertDialog(
      title: Text('盘点 · ${widget.cell.title}'),
      content: SizedBox(
        width: contentWidth,
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
// 智能记账结果
// ──────────────────────────────────────────────────────────────
class _ParsedRecord {
  final String cellId;
  final double amount;
  const _ParsedRecord(this.cellId, this.amount);
}

class _TagAddResult {
  final Set<String> selectedTags;
  final double amount;
  const _TagAddResult({required this.selectedTags, required this.amount});
}

class _TagAddDialog extends StatefulWidget {
  final List<String> allTags;
  final Bill bill;
  const _TagAddDialog({required this.allTags, required this.bill});

  @override
  State<_TagAddDialog> createState() => _TagAddDialogState();
}

class _TagAddDialogState extends State<_TagAddDialog> {
  final Set<String> _selected = {};
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int get _cellCount => widget.bill.cells
      .where((c) => c.tags.any(_selected.contains))
      .length;

  void _confirm() {
    if (_selected.isEmpty) return;
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null) return;
    Navigator.pop(context, _TagAddResult(selectedTags: _selected, amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('标签记账'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.allTags.map((tag) {
                final selected = _selected.contains(tag);
                final count = widget.bill.cells.where((c) => c.tags.contains(tag)).length;
                return FilterChip(
                  label: Text('$tag  ($count)'),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) _selected.add(tag); else _selected.remove(tag);
                  }),
                  selectedColor: Colors.orange.withValues(alpha: 0.2),
                  checkmarkColor: Colors.orange,
                  labelStyle: TextStyle(
                    color: selected ? Colors.orange : Colors.black87,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              autofocus: widget.allTags.length == 1,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                labelText: '金额',
                hintText: '输入金额',
                isDense: true,
                suffixText: _selected.isEmpty ? '' : '将记账 $_cellCount 个格子',
              ),
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _selected.isEmpty ? null : _confirm,
          child: const Text('确定记账'),
        ),
      ],
    );
  }
}

class _SmartAddResult {
  final List<_ParsedRecord> records;
  const _SmartAddResult(this.records);
}

// ──────────────────────────────────────────────────────────────
// 批量记账结果
// ──────────────────────────────────────────────────────────────
class _BatchAddResult {
  final List<String> selectedCellIds;
  final double amount;
  const _BatchAddResult({required this.selectedCellIds, required this.amount});
}

// ──────────────────────────────────────────────────────────────
// 批量记账弹框
// ──────────────────────────────────────────────────────────────
class _BatchAddDialog extends StatefulWidget {
  final List<Cell> cells;
  const _BatchAddDialog({required this.cells});

  @override
  State<_BatchAddDialog> createState() => _BatchAddDialogState();
}

class _BatchAddDialogState extends State<_BatchAddDialog> {
  final Set<String> _selected = {};
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cells = widget.cells;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 500 ? 400.0 : screenWidth * 0.9;
    final dialogHeight = MediaQuery.of(context).size.height * 0.6;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('批量记账'),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 金额输入
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
              decoration: const InputDecoration(
                labelText: '统一金额',
                hintText: '输入要记到所有选中单元格的金额',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('选择单元格 (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      onPressed: () => setState(() => _selected.addAll(cells.map((c) => c.cellId))),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // 单元格小格子列表
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 根据对话框宽度自适应列数
                  final width = constraints.maxWidth;
                  int crossAxisCount;
                  if (width >= 400) {
                    crossAxisCount = 5;
                  } else if (width >= 320) {
                    crossAxisCount = 4;
                  } else {
                    crossAxisCount = 3;
                  }
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.5,
                    ),
                itemCount: cells.length,
                itemBuilder: (_, i) {
                  final c = cells[i];
                  final isSelected = _selected.contains(c.cellId);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(c.cellId);
                        } else {
                          _selected.add(c.cellId);
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          c.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _selected.isEmpty || _amountCtrl.text.isEmpty
              ? null
              : () {
                  final amount = double.tryParse(_amountCtrl.text);
                  if (amount != null) {
                    Navigator.pop(context, _BatchAddResult(
                      selectedCellIds: _selected.toList(),
                      amount: amount,
                    ));
                  }
                },
          child: const Text('确定记账'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 智能记账弹框
// ──────────────────────────────────────────────────────────────
class _SmartAddDialog extends StatefulWidget {
  final List<Cell> cells;
  final List<_ParsedRecord> Function(String) onPreview;

  const _SmartAddDialog({
    required this.cells,
    required this.onPreview,
  });

  @override
  State<_SmartAddDialog> createState() => _SmartAddDialogState();
}

class _SmartAddDialogState extends State<_SmartAddDialog> {
  final _textCtrl = TextEditingController();
  List<_ParsedRecord> _preview = [];
  final Set<int> _removed = {};

  List<_ParsedRecord> get _activePreview =>
      [for (var i = 0; i < _preview.length; i++) if (!_removed.contains(i)) _preview[i]];

  void _updatePreview() {
    setState(() {
      _preview = widget.onPreview(_textCtrl.text);
      _removed.clear();
    });
  }

  /// 检测重复：活跃条目中同一 cellId 出现超过1次的 index 集合
  Set<int> _duplicateIndices() {
    final seen = <String>{};
    final dupes = <String>{};
    final activeIndices = [for (var i = 0; i < _preview.length; i++) if (!_removed.contains(i)) i];
    for (final i in activeIndices) {
      final id = _preview[i].cellId;
      if (!seen.add(id)) dupes.add(id);
    }
    return {
      for (final i in activeIndices)
        if (dupes.contains(_preview[i].cellId)) i,
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final cellMap = {for (var c in widget.cells) c.cellId: c};
    final active = _activePreview;
    final dupeIndices = _duplicateIndices();
    final hasDupes = dupeIndices.isNotEmpty;

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;
    final dialogHeight = MediaQuery.of(context).size.height * 0.7;

    return AlertDialog(
      title: const Text('智能记账'),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '粘贴文本...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => _updatePreview(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('预览结果', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${active.length}条记录', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
            if (hasDupes) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '存在重复格子，请移除重复行后再确认记账',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: active.isEmpty
                  ? const Center(child: Text('暂无匹配', style: TextStyle(color: Colors.black38)))
                  : ListView.builder(
                      itemCount: _preview.length,
                      itemBuilder: (_, rawIndex) {
                        if (_removed.contains(rawIndex)) return const SizedBox.shrink();
                        final rec = _preview[rawIndex];
                        final cell = cellMap[rec.cellId];
                        if (cell == null) return const SizedBox.shrink();
                        final isDupe = dupeIndices.contains(rawIndex);
                        return Container(
                          color: isDupe ? Colors.red.shade50 : null,
                          child: ListTile(
                            dense: true,
                            title: Text(
                              cell.title,
                              style: TextStyle(
                                color: isDupe ? Colors.red.shade700 : null,
                                fontWeight: isDupe ? FontWeight.w600 : null,
                              ),
                            ),
                            subtitle: Text(
                              '金额: ${fmt.format(rec.amount)}',
                              style: TextStyle(color: isDupe ? Colors.red.shade400 : null),
                            ),
                            trailing: TextButton(
                              onPressed: () => setState(() => _removed.add(rawIndex)),
                              child: Text(
                                '移除',
                                style: TextStyle(color: isDupe ? Colors.red.shade600 : null),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: (active.isEmpty || hasDupes)
              ? null
              : () => Navigator.pop(context, _SmartAddResult(active)),
          child: const Text('确认记账'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
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

/// 撤销记账用的辅助数据类：保存 bill、cell、record 的引用
class _RecordEntry {
  final Bill bill;
  final Cell cell;
  final CellRecord record;
  const _RecordEntry({required this.bill, required this.cell, required this.record});
}
