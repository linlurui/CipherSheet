import 'cell.dart';

/// 账单（表格）—— 一个账单就是一张表格，表格下有多个格子(Cell)
///
/// 三层结构：Ledger(账本) → Bill(账单/表格) → Cell(格子)
class Bill {
  final String billId;            // UUID
  final String ledgerId;         // 所属账本
  int orderIndex;                // 序号（用于排序与默认命名）
  String title;                  // 账单名称
  List<Cell> cells;              // 表格下的格子列表
  DateTime createdAt;
  DateTime updatedAt;

  Bill({
    required this.billId,
    required this.ledgerId,
    required this.orderIndex,
    required this.title,
    List<Cell>? cells,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : cells = cells ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 账单金额合计（所有格子之和）
  double get totalAmount =>
      cells.fold<double>(0, (sum, c) => sum + c.totalAmount);

  /// 账单计算金额合计（所有格子计算值之和）
  double get calculatedAmount =>
      cells.fold<double>(0, (sum, c) => sum + c.calculatedAmount());

  /// 按序号排序的格子列表
  List<Cell> get sortedCells =>
      List<Cell>.from(cells)..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  Map<String, dynamic> toJson() => {
        'bill_id': billId,
        'ledger_id': ledgerId,
        'order_index': orderIndex,
        'title': title,
        'cells': cells.map((c) => c.toJson()).toList(),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
        billId: j['bill_id'] as String,
        ledgerId: j['ledger_id'] as String,
        orderIndex: j['order_index'] as int,
        title: j['title'] as String,
        cells: ((j['cells'] as List?) ?? [])
            .map((e) => Cell.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updated_at'] as int),
      );

  Bill copyWith({
    int? orderIndex,
    String? title,
    List<Cell>? cells,
  }) {
    return Bill(
      billId: billId,
      ledgerId: ledgerId,
      orderIndex: orderIndex ?? this.orderIndex,
      title: title ?? this.title,
      cells: cells ?? List.from(this.cells),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
