import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/ledger.dart';
import '../../models/settlement.dart';
import '../../state/app_state.dart';

class SettlementScreen extends StatefulWidget {
  final String ledgerId;
  const SettlementScreen({super.key, required this.ledgerId});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  Settlement? _last;
  bool _busy = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSettle(BuildContext context, LedgerView view) async {
    final amt = double.tryParse(_input.text.trim());
    if (amt == null) return;
    setState(() => _busy = true);
    final s = await context.read<AppState>().settle(widget.ledgerId, amt);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final view = state.ledgerView(widget.ledgerId);
    if (view == null) {
      return const Scaffold(body: Center(child: Text('账本不存在')));
    }
    final fmt = NumberFormat('#,##0.##');
    final locked = !state.isUnlocked;
    final last = _last ?? view.latestSettlement;

    return Scaffold(
      appBar: AppBar(
        title: Text('结算 · ${view.ledger.name}'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '结算', icon: Icon(Icons.fact_check_outlined, size: 18)),
            Tab(text: '盘点记录', icon: Icon(Icons.history, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Tab 1: 结算操作 + 最新结果 + 图表
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerRow(view, fmt, locked),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('实结金额',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _input,
                          enabled: !locked,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: InputDecoration(
                            hintText: locked ? '请先解锁账本' : '请输入实际结算金额',
                            prefixIcon: const Icon(Icons.payments_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: (_busy || locked) ? null : () => _doSettle(context, view),
                            icon: const Icon(Icons.check),
                            label: const Text('确认结算'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (last != null) _summaryCard(last, fmt),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 280,
                      child: _ChartView(
                        view: view,
                        settlement: last,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tab 2: 盘点/结算记录列表
          _SettlementHistoryList(
            ledgerId: widget.ledgerId,
            fmt: fmt,
          ),
        ],
      ),
    );
  }

  Widget _headerRow(LedgerView view, NumberFormat fmt, bool locked) {
    final total = locked ? null : view.totalAmount();
    final expected = locked ? null : view.expectedAmount();
    return Row(
      children: [
        Expanded(child: _bigKv('格子合计', total == null ? '••••' : fmt.format(total))),
        Expanded(child: _bigKv('利率', '${view.ledger.interestRate.toStringAsFixed(2)}%')),
        Expanded(child: _bigKv('应结金额', expected == null ? '••••' : fmt.format(expected))),
      ],
    );
  }

  Widget _bigKv(String k, String v) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(v,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _summaryCard(Settlement s, NumberFormat fmt) {
    final positive = s.diff >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(positive ? Icons.trending_up : Icons.trending_down,
                    color: positive ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(positive ? '盘盈' : '盘亏',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: positive ? Colors.green : Colors.red)),
                const Spacer(),
                Text(DateFormat('yyyy-MM-dd HH:mm').format(s.settleTime),
                    style: const TextStyle(color: Colors.black45)),
              ],
            ),
            const SizedBox(height: 8),
            _kv('实结金额', fmt.format(s.inputAmount)),
            _kv('应结金额', fmt.format(s.expectedAmount)),
            _kv('应计利息', fmt.format(s.calculatedInterest)),
            _kv('差额', '${s.diff >= 0 ? '+' : ''}${fmt.format(s.diff)}'),
            _kv('账单/格子', '${s.billCount} / ${s.cellCount}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(k, style: const TextStyle(color: Colors.black54))),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// 盘点/结算记录列表
class _SettlementHistoryList extends StatelessWidget {
  final String ledgerId;
  final NumberFormat fmt;
  const _SettlementHistoryList({required this.ledgerId, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final view = state.ledgerView(ledgerId);
    if (view == null) return const SizedBox();

    final history = view.settlementHistory;
    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_outlined, size: 48, color: Colors.black26),
            SizedBox(height: 8),
            Text('暂无盘点记录', style: TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: history.length,
      itemBuilder: (ctx, i) {
        final s = history[i];
        final positive = s.diff >= 0;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              positive ? Icons.trending_up : Icons.trending_down,
              color: positive ? Colors.green : Colors.red,
            ),
            title: Text(
              '${positive ? '盘盈' : '盘亏'} ${s.diff >= 0 ? '+' : ''}${fmt.format(s.diff)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: positive ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            subtitle: Text(
              '实结: ${fmt.format(s.inputAmount)}  应结: ${fmt.format(s.expectedAmount)}  '
              '利率: ${s.interestRate.toStringAsFixed(1)}%  '
              '账单/格子: ${s.billCount}/${s.cellCount}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              DateFormat('yyyy-MM-dd\nHH:mm').format(s.settleTime),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
        );
      },
    );
  }
}

class _ChartView extends StatelessWidget {
  final LedgerView view;
  final Settlement? settlement;
  const _ChartView({required this.view, this.settlement});

  @override
  Widget build(BuildContext context) {
    final amounts = settlement?.cellAmountsSnapshot.isNotEmpty == true
        ? settlement!.cellAmountsSnapshot
        : view.bills.expand((b) => b.cells.map((c) => c.totalAmount)).toList();
    if (amounts.isEmpty) {
      return const Center(child: Text('暂无格子数据，无法绘制图表'));
    }
    final maxV =
        amounts.fold<double>(0, (a, b) => b > a ? b : a) * 1.2 + 1;
    final bars = <BarChartGroupData>[];
    for (var i = 0; i < amounts.length; i++) {
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: amounts[i],
          width: 8,
          borderRadius: BorderRadius.circular(2),
          color: Theme.of(context).colorScheme.primary,
        ),
      ]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('盘点图表 · 各格子金额分布',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(BarChartData(
            maxY: maxV,
            barGroups: bars,
            gridData: const FlGridData(show: true),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 38)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (amounts.length / 8).ceilToDouble().clamp(1, 50),
                  reservedSize: 28,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= amounts.length) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
          )),
        ),
      ],
    );
  }
}
