import 'package:flutter/material.dart';

import '../../../models/ledger.dart';
import '../../../models/cell.dart';
import '../../../models/unit.dart';

class LedgerSettingsResult {
  final double interestRate;
  final double? warningLimit;
  final double warningLimitPercent;
  LedgerSettingsResult(this.interestRate, this.warningLimit, this.warningLimitPercent);
}

/// 设置入口对话框：账本级别参数设置 + 盘点公式
class LedgerSettingsMenuDialog extends StatelessWidget {
  final Ledger ledger;
  final VoidCallback onOpenParameters;
  final VoidCallback onOpenFormula;
  final VoidCallback onOpenRules;
  const LedgerSettingsMenuDialog({
    super.key,
    required this.ledger,
    required this.onOpenParameters,
    required this.onOpenFormula,
    required this.onOpenRules,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('账本设置 · ${ledger.name}'),
      children: [
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('参数设置'),
          subtitle: const Text('增减参数（参数名 + 数值 + 单位），可在盘点公式中引用'),
          onTap: () {
            Navigator.pop(context);
            onOpenParameters();
          },
        ),
        ListTile(
          leading: const Icon(Icons.functions),
          title: const Text('盘点公式'),
          subtitle: const Text('设置盘盈/盘亏公式'),
          onTap: () {
            Navigator.pop(context);
            onOpenFormula();
          },
        ),
        ListTile(
          leading: const Icon(Icons.rule_outlined),
          title: const Text('规则设置'),
          subtitle: const Text('单元参数、一键盘点、结算开关'),
          onTap: () {
            Navigator.pop(context);
            onOpenRules();
          },
        ),
      ],
    );
  }
}

/// 参数设置：增减参数名（数值在单元格中设置）
class ParameterSettingsDialog extends StatefulWidget {
  final Ledger ledger;
  const ParameterSettingsDialog({super.key, required this.ledger});

  @override
  State<ParameterSettingsDialog> createState() =>
      _ParameterSettingsDialogState();
}

class _ParameterSettingsDialogState extends State<ParameterSettingsDialog> {
  late List<LedgerParameter> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.ledger.parameters
        .map((p) => LedgerParameter(key: p.key, value: p.value, unit: p.unit))
        .toList();
  }

  void _add() {
    setState(() {
      _items.add(LedgerParameter(key: '参数${_items.length + 1}', value: 0));
    });
  }

  void _remove(int i) {
    setState(() => _items.removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('参数设置'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '在此添加参数：参数名 + 数值 + 单位。\n例如：赔率 0.95 倍，利率 4.75 %',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final p = _items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        // 参数名
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            initialValue: p.key,
                            decoration: const InputDecoration(
                              labelText: '参数名',
                              isDense: true,
                            ),
                            onChanged: (v) => p.key = v.trim(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 数值（只允许数字）
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: p.value.toString(),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: '数值',
                              isDense: true,
                            ),
                            onChanged: (v) {
                              p.value = double.tryParse(v.trim()) ?? 0;
                            },
                          ),
                        ),
                        // 单位（下拉选择）
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<String>(
                              value: ParameterUnit.all.contains(p.unit) ? p.unit : '',
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: '单位',
                                isDense: true,
                              ),
                              items: ParameterUnit.all.map((u) => DropdownMenuItem(
                                value: u,
                                child: Text(ParameterUnit.getLabel(u), style: const TextStyle(fontSize: 12)),
                              )).toList(),
                              onChanged: (v) => setState(() => p.unit = v ?? ''),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _remove(i),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('添加参数'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            // 过滤无效项
            final cleaned = _items
                .where((p) => p.key.trim().isNotEmpty)
                .toList();
            Navigator.pop(context, cleaned);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 盘点公式设置：盘盈公式 + 盘亏公式各一个
class FormulaSettingsDialog extends StatefulWidget {
  final Ledger ledger;
  const FormulaSettingsDialog({super.key, required this.ledger});

  @override
  State<FormulaSettingsDialog> createState() => _FormulaSettingsDialogState();
}

class _FormulaSettingsDialogState extends State<FormulaSettingsDialog> {
  late TextEditingController _surplusCtrl;
  late TextEditingController _deficitCtrl;

  @override
  void initState() {
    super.initState();
    final f = widget.ledger.formulas;
    // 兼容旧版单一 'default' 公式：迁移到盘亏公式
    final legacy = f['default'] ?? '';
    _surplusCtrl = TextEditingController(text: f[SettlementEvent.surplus] ?? '');
    _deficitCtrl = TextEditingController(text: f[SettlementEvent.deficit] ?? legacy);
  }

  @override
  void dispose() {
    _surplusCtrl.dispose();
    _deficitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = widget.ledger.parameters;
    final paramHint = params.isEmpty
        ? '尚未定义参数，可在「参数设置」中添加'
        : '可用参数：${params.map((p) => p.key).join('、')}';
    final varHint = '内建变量：amount（格子金额）、multiplier（倍率）  $paramHint';

    Widget formulaField(String label, TextEditingController ctrl, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: '例如: amount * 赔率',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('盘点公式'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '盘点时手动选择盈/平/亏，选盈用盘盈公式，选亏用盘亏公式，选平直接等于记账金额。\n$varHint',
                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),
            formulaField('盘盈公式（应收）', _surplusCtrl, Colors.green.shade700),
            const SizedBox(height: 12),
            formulaField('盘亏公式（应付）', _deficitCtrl, Colors.red.shade700),
            const SizedBox(height: 6),
            const Text('支持: + - * / 和括号', style: TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              SettlementEvent.surplus: _surplusCtrl.text.trim(),
              SettlementEvent.deficit: _deficitCtrl.text.trim(),
            });
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class LedgerSettingsDialog extends StatefulWidget {
  final Ledger ledger;
  const LedgerSettingsDialog({super.key, required this.ledger});

  @override
  State<LedgerSettingsDialog> createState() => _LedgerSettingsDialogState();
}

class _LedgerSettingsDialogState extends State<LedgerSettingsDialog> {
  late TextEditingController _rate;
  late TextEditingController _limitPercent;
  late TextEditingController _limitOverride;
  bool _autoLimit = false;

  @override
  void initState() {
    super.initState();
    _rate = TextEditingController(text: widget.ledger.interestRate.toString());
    _limitPercent = TextEditingController(text: widget.ledger.warningLimitPercent.toString());
    _limitOverride = TextEditingController(
        text: widget.ledger.warningLimitOverride?.toString() ?? '');
    _autoLimit = widget.ledger.warningLimitOverride == null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('账本设置 · ${widget.ledger.name}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '利率 (%)',
                helperText: '动态可调，参与结算计算 (expected = total * (1+rate/100))',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _limitPercent,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '预警限额比例 (%)',
                helperText: '自动计算: 总额 × 此比例，如 2 表示 2%',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _autoLimit,
                  onChanged: (v) =>
                      setState(() => _autoLimit = v ?? false),
                ),
                const Expanded(child: Text('使用自动计算（忽略手动限额）')),
              ],
            ),
            if (!_autoLimit)
              TextField(
                controller: _limitOverride,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: '手动预警限额'),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '调整后立刻生效，并写入下一条 state_payload (DL 状态链将记录此次变更)。',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final r = double.tryParse(_rate.text.trim()) ??
                widget.ledger.interestRate;
            final pct = double.tryParse(_limitPercent.text.trim()) ??
                widget.ledger.warningLimitPercent;
            double? lim;
            if (!_autoLimit) {
              lim = double.tryParse(_limitOverride.text.trim());
            }
            Navigator.pop(context, LedgerSettingsResult(r, lim, pct));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 规则设置对话框：三个开关 + 未选中默认盘点
class RulesSettingsDialog extends StatefulWidget {
  final LedgerRules rules;
  const RulesSettingsDialog({super.key, required this.rules});

  @override
  State<RulesSettingsDialog> createState() => _RulesSettingsDialogState();
}

class _RulesSettingsDialogState extends State<RulesSettingsDialog> {
  late bool _enableCellParams;
  late bool _enableBatchSettle;
  late String _batchDefault;
  late bool _disableSettle;

  @override
  void initState() {
    super.initState();
    _enableCellParams  = widget.rules.enableCellParams;
    _enableBatchSettle = widget.rules.enableBatchSettle;
    _batchDefault      = widget.rules.batchSettleDefault;
    _disableSettle     = widget.rules.disableSettle;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('规则设置'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('启用单元参数设置'),
              subtitle: const Text(
                '关闭时格子不显示参数入口，所有格子统一使用账本参数默认值',
                style: TextStyle(fontSize: 11),
              ),
              value: _enableCellParams,
              onChanged: (v) => setState(() => _enableCellParams = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('启用一键盘点'),
              subtitle: const Text(
                '开启后格子不显示盘点图标，改为账单旁一键多选盘点',
                style: TextStyle(fontSize: 11),
              ),
              value: _enableBatchSettle,
              onChanged: (v) => setState(() => _enableBatchSettle = v),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: _enableBatchSettle
                  ? Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                      child: Row(
                        children: [
                          const Text('未选中单元默认-',
                              style: TextStyle(fontSize: 13, color: Colors.black54)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _batchDefault,
                            isDense: true,
                            items: DefaultSettleAction.all
                                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _batchDefault = v ?? DefaultSettleAction.surplus),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('关闭结算'),
              subtitle: const Text(
                '开启后格子不显示结算（实结金额）图标',
                style: TextStyle(fontSize: 11),
              ),
              value: _disableSettle,
              onChanged: (v) => setState(() => _disableSettle = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            LedgerRules(
              enableCellParams:   _enableCellParams,
              enableBatchSettle:  _enableBatchSettle,
              batchSettleDefault: _batchDefault,
              disableSettle:      _disableSettle,
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
