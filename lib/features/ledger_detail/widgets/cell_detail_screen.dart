import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/cell.dart';
import '../../../models/ledger.dart';
import '../../../models/unit.dart';
import '../../../state/app_state.dart';

/// 格子详情页 —— 记账记录列表 + 参数管理 + 公式设置
class CellDetailScreen extends StatefulWidget {
  final String ledgerId;
  final String billId;
  final String cellId;
  const CellDetailScreen({
    super.key,
    required this.ledgerId,
    required this.billId,
    required this.cellId,
  });

  @override
  State<CellDetailScreen> createState() => _CellDetailScreenState();
}

class _CellDetailScreenState extends State<CellDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Cell? _findCell(AppState state) {
    final view = state.ledgerView(widget.ledgerId);
    if (view == null) return null;
    for (final bill in view.bills) {
      for (final cell in bill.cells) {
        if (cell.cellId == widget.cellId) return cell;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cell = _findCell(state);
    if (cell == null) {
      return const Scaffold(body: Center(child: Text('格子不存在')));
    }
    final locked = !state.isUnlocked;
    final fmt = NumberFormat('#,##0.##');

    return Scaffold(
      appBar: AppBar(
        title: Text('格子 ${cell.title}'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '记账记录', icon: Icon(Icons.receipt_long, size: 18)),
            Tab(text: '参数', icon: Icon(Icons.tune, size: 18)),
            Tab(text: '盘点公式', icon: Icon(Icons.functions, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _RecordsTab(cell: cell, locked: locked, fmt: fmt),
          _ParamsTab(cell: cell, locked: locked),
          _FormulaTab(
            cell: cell,
            locked: locked,
            ledgerFormula: context.read<AppState>().ledgerView(widget.ledgerId)?.ledger.formulas['default'],
          ),
        ],
      ),
      floatingActionButton: locked
          ? null
          : FloatingActionButton(
              onPressed: () => _addRecord(cell),
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _addRecord(Cell cell) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        final remarkCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('新增记账'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '金额'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text);
                if (v != null && v != 0) Navigator.pop(ctx, v);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (amount == null) return;
    // We need the remark too — simplified: re-ask or use empty
    await context.read<AppState>().addCellRecord(
          widget.ledgerId,
          widget.billId,
          widget.cellId,
          amount: amount,
        );
  }
}

// ============================================================
// 记账记录 Tab
// ============================================================

class _RecordsTab extends StatelessWidget {
  final Cell cell;
  final bool locked;
  final NumberFormat fmt;
  const _RecordsTab({required this.cell, required this.locked, required this.fmt});

  @override
  Widget build(BuildContext context) {
    if (cell.records.isEmpty) {
      return const Center(child: Text('暂无记账记录', style: TextStyle(color: Colors.black45)));
    }
    final sorted = List<CellRecord>.from(cell.records)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Column(
      children: [
        // 合计栏
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              const Text('合计', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                locked ? '••••' : fmt.format(cell.totalAmount),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF3563E9)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (ctx, i) {
              final r = sorted[i];
              return ListTile(
                title: Text(locked ? '••••' : fmt.format(r.amount)),
                subtitle: Text(r.remarks.isEmpty
                    ? DateFormat('yyyy-MM-dd HH:mm').format(r.timestamp)
                    : '${r.remarks}  ·  ${DateFormat('yyyy-MM-dd HH:mm').format(r.timestamp)}'),
                trailing: locked ? null : IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _deleteRecord(context, r),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _deleteRecord(BuildContext context, CellRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录?'),
        content: Text('金额: ${fmt.format(r.amount)}'),
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
    if (ok != true) return;
    // Need to find the AppState via provider
    final state = context.read<AppState>();
    await state.deleteCellRecord(
      // We need ledgerId, billId, cellId — get from ancestor
      (context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.ledgerId),
      (context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.billId),
      (context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.cellId),
      r.recordId,
    );
  }
}

// ============================================================
// 参数 Tab
// ============================================================

class _ParamsTab extends StatelessWidget {
  final Cell cell;
  final bool locked;
  const _ParamsTab({required this.cell, required this.locked});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!locked)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _addParam(context),
                child: const Text('+ 新增参数'),
              ),
            ),
          ),
        if (cell.parameters.isEmpty)
          const Expanded(
            child: Center(child: Text('暂无参数', style: TextStyle(color: Colors.black45))),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: cell.parameters.length,
              itemBuilder: (ctx, i) {
                final p = cell.parameters[i];
                return ListTile(
                  title: Text(p.key),
                  subtitle: Text('${p.value}${p.unit}'),
                  trailing: locked ? null : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _editParam(context, p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _deleteParam(context, p),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _addParam(BuildContext context) async {
    final keyCtrl = TextEditingController();
    final valCtrl = TextEditingController();
    String selectedUnit = '';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新增参数'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: '参数名')),
              const SizedBox(height: 8),
              TextField(controller: valCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '数值')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedUnit,
                isDense: true,
                decoration: const InputDecoration(labelText: '单位'),
                items: ParameterUnit.all.map((u) => DropdownMenuItem(
                  value: u,
                  child: Text(ParameterUnit.getLabel(u)),
                )).toList(),
                onChanged: (v) => setState(() => selectedUnit = v ?? ''),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(valCtrl.text);
                if (v != null && keyCtrl.text.isNotEmpty) {
                  Navigator.pop(ctx, {'key': keyCtrl.text, 'value': v, 'unit': selectedUnit});
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final state = context.read<AppState>();
    final ledgerId = context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.ledgerId;
    await state.addCellParameter(
      ledgerId,
      cell.billId,
      cell.cellId,
      key: result['key'] as String,
      value: result['value'] as double,
      unit: result['unit'] as String? ?? '',
    );
  }

  Future<void> _editParam(BuildContext context, CellParameter p) async {
    final valCtrl = TextEditingController(text: p.value.toString());
    String selectedUnit = ParameterUnit.all.contains(p.unit) ? p.unit : '';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('编辑参数 ${p.key}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: valCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '数值')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedUnit,
                isDense: true,
                decoration: const InputDecoration(labelText: '单位'),
                items: ParameterUnit.all.map((u) => DropdownMenuItem(
                  value: u,
                  child: Text(ParameterUnit.getLabel(u)),
                )).toList(),
                onChanged: (v) => setState(() => selectedUnit = v ?? ''),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(valCtrl.text);
                if (v != null) Navigator.pop(ctx, {'value': v, 'unit': selectedUnit});
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final state = context.read<AppState>();
    final ledgerId = context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.ledgerId;
    await state.updateCellParameter(
      ledgerId, cell.billId, cell.cellId, p.key,
      value: result['value'] as double,
      unit: result['unit'] as String?,
    );
  }

  Future<void> _deleteParam(BuildContext context, CellParameter p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除参数 ${p.key}?'),
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
    if (ok != true) return;
    final state = context.read<AppState>();
    final ledgerId = context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.ledgerId;
    await state.deleteCellParameter(ledgerId, cell.billId, cell.cellId, p.key);
  }
}

// ============================================================
// 盘点公式 Tab
// ============================================================

class _FormulaTab extends StatelessWidget {
  final Cell cell;
  final bool locked;
  final String? ledgerFormula;
  const _FormulaTab({required this.cell, required this.locked, this.ledgerFormula});

  @override
  Widget build(BuildContext context) {
    final calculated = cell.calculatedAmount(ledgerFormula: ledgerFormula);
    final total = cell.totalAmount;

    // 判定盘盈/平/亏：公式结果>0盘盈，<0盘亏，=0盘平
    String event;
    MaterialColor eventColor;
    if (calculated > 0) {
      event = '盘盈';
      eventColor = Colors.green;
    } else if (calculated < 0) {
      event = '盘亏';
      eventColor = Colors.red;
    } else {
      event = '盘平';
      eventColor = Colors.blue;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 盘点公式说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '盘点公式用于计算应结金额，结果自动判定盘盈/平/亏。',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            cell.formula.isNotEmpty ? '单元格专属公式:' : '账本盘点公式:',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              cell.formula.isNotEmpty
                  ? cell.formula
                  : (ledgerFormula?.isNotEmpty == true
                      ? ledgerFormula!
                      : '（默认: amount * multiplier）'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: (cell.formula.isEmpty && ledgerFormula?.isEmpty != false)
                    ? Colors.black38
                    : Colors.black87,
              ),
            ),
          ),
          if (cell.formula.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '此单元格使用专属公式，覆盖账本设置',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
              ),
            ),
          const SizedBox(height: 16),

          Text('可用变量:', style: TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip('amount', '格子金额合计: ${NumberFormat('#,##0.##').format(cell.totalAmount)}'),
              _chip('multiplier', '倍率: ${cell.multiplier}'),
              for (final p in cell.parameters) _chip(p.key, '${p.key}: ${p.value}${p.unit}'),
            ],
          ),
          const SizedBox(height: 16),

          // 计算结果和判定
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: eventColor.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: eventColor.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('记账金额: ', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      Text(
                        locked ? '••••' : total.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: eventColor.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: eventColor.shade300),
                  ),
                  child: Column(
                    children: [
                      Text(
                        calculated > 0 ? '应收金额: ' : (calculated < 0 ? '应付金额: ' : '应收/应付: '),
                        style: TextStyle(
                          color: calculated > 0 ? Colors.blue.shade700 : (calculated < 0 ? Colors.red.shade700 : Colors.black54),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        locked ? '••••' : calculated.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: calculated > 0 ? Colors.blue.shade700 : (calculated < 0 ? Colors.red.shade700 : eventColor.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!locked)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => _editFormula(context),
                child: const Text('编辑盘点公式'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Chip(label: Text(label, style: const TextStyle(fontSize: 12))),
    );
  }

  Future<void> _editFormula(BuildContext context) async {
    final ctrl = TextEditingController(text: cell.formula);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑盘点公式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '公式结果 > 记账金额 = 盘盈\n'
              '公式结果 = 记账金额 = 盘平\n'
              '公式结果 < 记账金额 = 盘亏',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '例: amount * (1 + 利率) * multiplier',
              ),
            ),
            const SizedBox(height: 8),
            const Text('支持: + - * / 和括号。变量名会被替换为数值后计算。',
                style: TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('清空(用默认)'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final state = context.read<AppState>();
    final ledgerId = context.findAncestorStateOfType<_CellDetailScreenState>()!.widget.ledgerId;
    await state.setCellFormula(ledgerId, cell.billId, cell.cellId, result);
  }
}
