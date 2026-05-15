/// 结算（盘点）记录
class Settlement {
  final String settlementId;
  final String ledgerId;
  final DateTime settleTime;
  final double inputAmount;          // 用户填入的实际结算金额
  final double interestRate;         // 当前账本利率（动态）
  final double expectedAmount;       // 应结金额
  final double calculatedInterest;   // 应计利息
  final double diff;                 // 盘盈/盘亏 = inputAmount - expectedAmount
  final String? encryptedInputAmount; // 助记词加密后的密文 (Base64)
  final List<double> cellAmountsSnapshot; // 结算快照（每个格子金额）用于绘图
  final int billCount;               // 结算时账单数
  final int cellCount;               // 结算时格子数

  Settlement({
    required this.settlementId,
    required this.ledgerId,
    required this.settleTime,
    required this.inputAmount,
    required this.interestRate,
    required this.expectedAmount,
    required this.calculatedInterest,
    required this.diff,
    this.encryptedInputAmount,
    this.cellAmountsSnapshot = const [],
    this.billCount = 0,
    this.cellCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'settlement_id': settlementId,
        'ledger_id': ledgerId,
        'settle_time': settleTime.millisecondsSinceEpoch,
        'input_amount': inputAmount,
        'interest_rate': interestRate,
        'expected_amount': expectedAmount,
        'calculated_interest': calculatedInterest,
        'diff': diff,
        if (encryptedInputAmount != null) 'encrypted_input_amount': encryptedInputAmount,
        'cell_amounts_snapshot': cellAmountsSnapshot,
        'bill_count': billCount,
        'cell_count': cellCount,
      };

  factory Settlement.fromJson(Map<String, dynamic> j) {
    // 兼容旧字段 bill_amounts_snapshot
    final snapshot = ((j['cell_amounts_snapshot'] as List?) ??
        (j['bill_amounts_snapshot'] as List?) ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    return Settlement(
      settlementId: j['settlement_id'] as String,
      ledgerId: j['ledger_id'] as String,
      settleTime: DateTime.fromMillisecondsSinceEpoch(j['settle_time'] as int),
      inputAmount: (j['input_amount'] as num).toDouble(),
      interestRate: (j['interest_rate'] as num).toDouble(),
      expectedAmount: (j['expected_amount'] as num).toDouble(),
      calculatedInterest: (j['calculated_interest'] as num).toDouble(),
      diff: (j['diff'] as num).toDouble(),
      encryptedInputAmount: j['encrypted_input_amount'] as String?,
      cellAmountsSnapshot: snapshot,
      billCount: (j['bill_count'] as int?) ?? 0,
      cellCount: (j['cell_count'] as int?) ?? snapshot.length,
    );
  }
}
