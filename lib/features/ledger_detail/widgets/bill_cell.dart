import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/cell.dart';
import '../../../models/ledger.dart';
import '../../../theme.dart';

/// 宫格中的单个格子卡片
class BillCell extends StatelessWidget {
  final Cell cell;
  final bool locked;
  final double interestRate;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onShowRecords;
  final VoidCallback? onSettle;
  final VoidCallback? onMarkSettled;
  final VoidCallback? onSetParams;
  final VoidCallback? onDelete;
  final VoidCallback? onPredict;

  const BillCell({
    super.key,
    required this.cell,
    required this.locked,
    required this.interestRate,
    required this.onTap,
    required this.onLongPress,
    required this.onShowRecords,
    this.onSettle,
    this.onMarkSettled,
    this.onSetParams,
    this.onDelete,
    this.onPredict,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.##');
    final color = cellColorFor(cell.multiplier);
    final textColor = cellTextColorFor(cell.multiplier);

    final isSettled = cell.settlementEvent != null;

    // 盈亏：已盘点用结算金额，未盘点用旧利率算法
    final pnl = isSettled && cell.settlementAmount != null
        ? cell.settlementAmount!
        : cell.totalAmount * (interestRate / 100.0) * cell.multiplier;


    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.black12,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: ClipRect(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 序号 + 倍率
                  Row(
                    children: [
                      Text('#${cell.orderIndex.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: textColor)),
                      if (cell.multiplier != 1.0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('${cell.multiplier}x',
                              style: TextStyle(fontSize: 10, color: textColor)),
                        ),
                    ],
                  ),
            const SizedBox(height: 4),
            // 金额（蓝色）
            Text(
              locked ? '••••' : fmt.format(cell.totalAmount),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3563E9)),
            ),
            // 参数列表（全部显示）
            if (cell.parameters.isNotEmpty && !locked) ...[
              const SizedBox(height: 2),
              ...cell.parameters.map((p) => Text(
                '${p.key}: ${p.value}${p.unit}',
                style: TextStyle(
                    fontSize: 9, color: textColor.withValues(alpha: 0.65)),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )),
            ],
            const SizedBox(height: 4),
            // 未盘点时显示盈亏估算；已盘点时显示事件标签+结算金额并排
            if (!locked) ...[
              if (isSettled) ...[
                // 盘点金额（公式结果）
                if (cell.settlementAmount != null && cell.settlementEvent != SettlementEvent.even)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(builder: (context) {
                        final amt = cell.settlementAmount ?? 0;
                        final displayEvent = amt > 0
                            ? SettlementEvent.surplus
                            : amt < 0
                                ? SettlementEvent.deficit
                                : SettlementEvent.even;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _eventColor(displayEvent).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(displayEvent,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _eventColor(displayEvent))),
                        );
                      }),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          // 金额为0时不显示正负号
                          cell.settlementAmount == 0
                              ? fmt.format(0)
                              : '${cell.settlementAmount! > 0 ? '+' : ''}${fmt.format(cell.settlementAmount!)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: cell.settlementAmount! >= 0 ? Colors.blue.shade700 : Colors.red.shade700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else
                  Builder(builder: (context) {
                    final displayEvent = cell.settlementEvent ?? SettlementEvent.even;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _eventColor(displayEvent).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(displayEvent,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _eventColor(displayEvent))),
                    );
                  }),
                // 已结算金额（用户实际输入）
                if (cell.settledAmount != null)
                  Text(
                    '已结 ${cell.settledAmount! >= 0 ? '+' : ''}${fmt.format(cell.settledAmount!)}',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ]
              else if (cell.totalAmount > 0)
                Text(
                  '${pnl >= 0 ? '+' : ''}${fmt.format(pnl)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: pnl >= 0 ? Colors.green.shade800 : Colors.red.shade700,
                  ),
                ),
            ],
            // 记录数（未盘点时显示）
            if (cell.records.length > 1 && !isSettled)
              Text('${cell.records.length}笔',
                  style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            // 底部图标行
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 4,
              overflowSpacing: 0,
              children: [
                // 记录清单图标
                if (cell.records.isNotEmpty)
                  GestureDetector(
                    onTap: onShowRecords,
                    child: Icon(Icons.list_alt,
                        size: 16, color: textColor.withValues(alpha: 0.7)),
                  ),
                // 结算图标（已盘点且非盘平时显示）
                if (isSettled && cell.settlementEvent != SettlementEvent.even && onSettle != null)
                  GestureDetector(
                    onTap: onSettle,
                    child: Icon(Icons.account_balance_wallet_outlined,
                        size: 16,
                        color: _eventColor(cell.settlementEvent!)),
                  ),
                // 参数设置图标
                if (onSetParams != null)
                  GestureDetector(
                    onTap: onSetParams,
                    child: Icon(Icons.tune,
                        size: 16, color: textColor.withValues(alpha: 0.5)),
                  ),
                // 盘点图标（始终显示，支持重新盘点）
                if (onMarkSettled != null)
                  GestureDetector(
                    onTap: onMarkSettled,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3563E9).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.task_alt,
                          size: 18, color: Color(0xFF3563E9)),
                    ),
                  ),
                // 预测图标
                if (onPredict != null)
                  GestureDetector(
                    onTap: onPredict,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.insights,
                          size: 18, color: Colors.orange),
                    ),
                  ),
              ],
            ),
          ],
        ),
              // 标签水印（右上角，约露出八成）
              if (cell.tags.isNotEmpty)
                Positioned(
                  top: -13,
                  right: -6,
                  child: Text(
                    cell.tags.first,
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.black.withValues(alpha: 0.08),
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _eventColor(String event) {
    switch (event) {
      case SettlementEvent.surplus:
        return Colors.green;
      case SettlementEvent.deficit:
        return Colors.red;
      case SettlementEvent.even:
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }
}
