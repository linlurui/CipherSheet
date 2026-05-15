import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'unit.dart';

/// 单元格参数（动态增减，不写死）
class CellParameter {
  final String key;       // 参数名，如 "利率"、"手续费"
  double value;           // 参数值
  String unit;            // 单位，如 "%", "元"

  CellParameter({
    required this.key,
    required this.value,
    this.unit = '',
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'unit': unit,
      };

  factory CellParameter.fromJson(Map<String, dynamic> j) => CellParameter(
        key: j['key'] as String,
        value: (j['value'] as num).toDouble(),
        unit: (j['unit'] as String?) ?? '',
      );
}

/// 一笔记账记录（格子内的明细行）
class CellRecord {
  final String recordId;
  double amount;
  DateTime timestamp;
  String remarks;
  DateTime createdAt;
  DateTime updatedAt;

  CellRecord({
    required this.recordId,
    required this.amount,
    required this.timestamp,
    this.remarks = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'record_id': recordId,
        'amount': amount,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'remarks': remarks,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory CellRecord.fromJson(Map<String, dynamic> j) => CellRecord(
        recordId: j['record_id'] as String,
        amount: (j['amount'] as num).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['timestamp'] as int),
        remarks: (j['remarks'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            j['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            j['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      );
}

/// 单元格（格子）—— 最小记账单元
///
/// 每个格子有独立参数（利率、倍率等动态增减）和公式，
/// 内含多条记账记录（CellRecord），支持记账详情列表。
class Cell {
  final String cellId;
  final String billId;           // 所属账单(表格)
  int orderIndex;                // 序号（01, 02, ...）
  String title;                  // 名称，默认 "01","02"...
  double multiplier;             // 倍率
  String formula;                // 计算公式，如 "amount * (1 + 利率/100) * multiplier"
  List<CellParameter> parameters; // 动态参数列表
  List<CellRecord> records;      // 记账记录列表
  DateTime createdAt;
  DateTime updatedAt;
  String? encryptedAmount;       // 助记词加密密文
  String? settlementEvent;       // 盘点事件：盘盈/盘亏/盘平
  double? settlementAmount;      // 公式计算的应收/应付金额
  double? settledAmount;         // 用户实际结算金额

  Cell({
    required this.cellId,
    required this.billId,
    required this.orderIndex,
    required this.title,
    this.multiplier = 1.0,
    this.formula = '',
    List<CellParameter>? parameters,
    List<CellRecord>? records,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.encryptedAmount,
    this.settlementEvent,
    this.settlementAmount,
    this.settledAmount,
  })  : parameters = parameters ?? [],
        records = records ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 格子金额合计（所有记录之和）
  double get totalAmount =>
      records.fold<double>(0, (sum, r) => sum + r.amount);

  /// 根据公式和参数计算应得金额（支持单位自动换算）
  /// [ledgerFormula] - 账本级别的默认公式（当 cell.formula 为空时使用）
  double calculatedAmount({String? ledgerFormula}) {
    // 优先使用单元格自己的公式，其次使用账本公式，最后使用默认公式
    final effectiveFormula = formula.isNotEmpty
        ? formula
        : (ledgerFormula?.isNotEmpty == true
            ? ledgerFormula!
            : '');

    if (effectiveFormula.isEmpty) return totalAmount * multiplier;

    // 简易公式引擎：替换变量名 → 换算后的值，然后 eval
    String expr = effectiveFormula;
    expr = expr.replaceAll('amount', totalAmount.toString());
    expr = expr.replaceAll('multiplier', multiplier.toString());
    for (final p in parameters) {
      // 使用单位换算后的实际值
      final computedValue = p.value * ParameterUnit.getFactor(p.unit);
      expr = expr.replaceAll(p.key, computedValue.toString());
    }
    try {
      return _evalSimple(expr);
    } catch (_) {
      return totalAmount * multiplier;
    }
  }

  /// 极简表达式求值（支持 + - * / 和括号）
  static double _evalSimple(String expr) {
    final tokens = _tokenize(expr);
    final pos = [0];
    return _parseExpr(tokens, pos);
  }

  static List<String> _tokenize(String s) {
    final result = <String>[];
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      if ('0123456789.'.contains(ch)) {
        buf.write(ch);
      } else {
        if (buf.isNotEmpty) {
          result.add(buf.toString());
          buf.clear();
        }
        if (ch.trim().isNotEmpty) result.add(ch);
      }
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }

  static double _parseExpr(List<String> tokens, List<int> pos) {
    // 处理开头的一元负号
    double sign = 1.0;
    if (pos[0] < tokens.length && tokens[pos[0]] == '-') {
      sign = -1.0;
      pos[0]++;
    }
    double left = sign * _parseTerm(tokens, pos);
    while (pos[0] < tokens.length) {
      final op = tokens[pos[0]];
      if (op == '+') { pos[0]++; left += _parseTerm(tokens, pos); }
      else if (op == '-') { pos[0]++; left -= _parseTerm(tokens, pos); }
      else break;
    }
    return left;
  }

  static double _parseTerm(List<String> tokens, List<int> pos) {
    double left = _parseFactor(tokens, pos);
    while (pos[0] < tokens.length) {
      final op = tokens[pos[0]];
      if (op == '*') { pos[0]++; left *= _parseFactor(tokens, pos); }
      else if (op == '/') { pos[0]++; left /= _parseFactor(tokens, pos); }
      else break;
    }
    return left;
  }

  static double _parseFactor(List<String> tokens, List<int> pos) {
    if (pos[0] >= tokens.length) return 0;
    final t = tokens[pos[0]];
    if (t == '(') {
      pos[0]++;
      final v = _parseExpr(tokens, pos);
      if (pos[0] < tokens.length && tokens[pos[0]] == ')') pos[0]++;
      return v;
    }
    // 处理因子级一元负号（如括号内）
    if (t == '-') {
      pos[0]++;
      return -_parseFactor(tokens, pos);
    }
    pos[0]++;
    return double.tryParse(t) ?? 0;
  }

  /// 用于写入 state_payload 的摘要
  Map<String, dynamic> toDigest() {
    final canonical = jsonEncode({
      'c': cellId,
      'i': orderIndex,
      'a': totalAmount,
      'm': multiplier,
      'r': records.length,
    });
    final hash = sha256.convert(utf8.encode(canonical)).toString();
    return {
      'cell_id': cellId,
      'order_index': orderIndex,
      'title': title,
      'hash': hash,
      'record_count': records.length,
    };
  }

  Map<String, dynamic> toJson() => {
        'cell_id': cellId,
        'bill_id': billId,
        'order_index': orderIndex,
        'title': title,
        'multiplier': multiplier,
        'formula': formula,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        if (encryptedAmount != null) 'encrypted_amount': encryptedAmount,
        if (settlementEvent != null) 'settlement_event': settlementEvent,
        if (settlementAmount != null) 'settlement_amount': settlementAmount,
        if (settledAmount != null) 'settled_amount': settledAmount,
      };

  factory Cell.fromJson(Map<String, dynamic> j) => Cell(
        cellId: j['cell_id'] as String,
        billId: j['bill_id'] as String,
        orderIndex: j['order_index'] as int,
        title: j['title'] as String,
        multiplier: (j['multiplier'] as num?)?.toDouble() ?? 1.0,
        formula: (j['formula'] as String?) ?? '',
        parameters: ((j['parameters'] as List?) ?? [])
            .map((e) => CellParameter.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        records: ((j['records'] as List?) ?? [])
            .map((e) => CellRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            j['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            j['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        encryptedAmount: j['encrypted_amount'] as String?,
        settlementEvent: j['settlement_event'] as String?,
        settlementAmount: (j['settlement_amount'] as num?)?.toDouble(),
        settledAmount: (j['settled_amount'] as num?)?.toDouble(),
      );

  Cell copyWith({
    int? orderIndex,
    String? title,
    double? multiplier,
    String? formula,
    List<CellParameter>? parameters,
    List<CellRecord>? records,
    String? encryptedAmount,
    String? settlementEvent,
    double? settlementAmount,
    double? settledAmount,
    bool clearSettlement = false,
  }) {
    return Cell(
      cellId: cellId,
      billId: billId,
      orderIndex: orderIndex ?? this.orderIndex,
      title: title ?? this.title,
      multiplier: multiplier ?? this.multiplier,
      formula: formula ?? this.formula,
      parameters: parameters ?? List.from(this.parameters),
      records: records ?? List.from(this.records),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      encryptedAmount: encryptedAmount ?? this.encryptedAmount,
      settlementEvent: clearSettlement ? null : (settlementEvent ?? this.settlementEvent),
      settlementAmount: clearSettlement ? null : (settlementAmount ?? this.settlementAmount),
      settledAmount: clearSettlement ? null : (settledAmount ?? this.settledAmount),
    );
  }
}
