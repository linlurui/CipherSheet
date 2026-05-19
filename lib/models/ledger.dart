import 'bill.dart';
import 'settlement.dart';
import 'unit.dart';

/// 账本级参数（参数名 + 金额/数值）
/// 例如：{key: '赔率', value: 1.8, unit: '倍'}、{key: '利率', value: 5, unit: '%'}
class LedgerParameter {
  String key;
  double value;
  String unit;

  LedgerParameter({required this.key, required this.value, this.unit = ''});

  /// 获取换算后的实际值（用于公式计算）
  double get computedValue => value * ParameterUnit.getFactor(unit);

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'unit': unit,
      };

  factory LedgerParameter.fromJson(Map<String, dynamic> j) => LedgerParameter(
        key: j['key'] as String,
        value: (j['value'] as num).toDouble(),
        unit: (j['unit'] as String?) ?? '',
      );

  /// 验证单位是否有效，无效时返回空字符串
  String get validatedUnit => ParameterUnit.all.contains(unit) ? unit : '';
}

/// 盘点事件枚举（用于公式分类）
class SettlementEvent {
  static const String surplus = '盘盈';
  static const String deficit = '盘亏';
  static const String even = '盘平';
  static const List<String> all = [surplus, deficit, even];
}

/// 未选中单元默认盘点处理
class DefaultSettleAction {
  static const String surplus  = '盘盈';
  static const String even     = '盘平';
  static const String deficit  = '盘亏';
  static const String none     = '不处理';
  static const List<String> all = [surplus, deficit, even, none];
}

/// 账本规则（开关 + 默认行为）
class LedgerRules {
  /// 启用单元参数设置（关闭时所有格子使用账本级统一参数，格子内不显示参数入口）
  bool enableCellParams;

  /// 启用一键盘点（开启后格子内不显示盘点图标，改为账单标题旁显示一键盘点按钮）
  bool enableBatchSettle;

  /// 一键盘点时未选中格子的默认处理（'盘盈'/'盘平'/'盘亏'/'不处理'）
  String batchSettleDefault;

  /// 关闭结算（开启后格子内不显示结算图标）
  bool disableSettle;

  LedgerRules({
    this.enableCellParams  = false,
    this.enableBatchSettle = true,
    this.batchSettleDefault = DefaultSettleAction.surplus,
    this.disableSettle     = false,
  });

  Map<String, dynamic> toJson() => {
    'enable_cell_params':    enableCellParams,
    'enable_batch_settle':   enableBatchSettle,
    'batch_settle_default':  batchSettleDefault,
    'disable_settle':        disableSettle,
  };

  factory LedgerRules.fromJson(Map<String, dynamic> j) => LedgerRules(
    enableCellParams:   (j['enable_cell_params']  as bool?) ?? false,
    enableBatchSettle:  (j['enable_batch_settle'] as bool?) ?? true,
    batchSettleDefault: (j['batch_settle_default'] as String?) ?? DefaultSettleAction.surplus,
    disableSettle:      (j['disable_settle']      as bool?) ?? false,
  );
}

/// 账本
class Ledger {
  final String id;                  // UUID
  String name;
  DateTime createdAt;
  DateTime updatedAt;

  /// 动态利率（百分比，例如 47 表示 47%）。可在设置中随时调整。
  double interestRate;

  /// 预警限额比例（百分比，动态可调，不写死）
  double warningLimitPercent;

  /// 预警限额，手动覆盖值（优先级高于 warningLimitPercent 自动计算）
  double? warningLimitOverride;

  /// 账本级参数（可增减），可在公式中引用
  List<LedgerParameter> parameters;

  /// 各盘点事件对应公式：event -> expression
  Map<String, String> formulas;

  /// 账本规则（开关集合）
  LedgerRules rules;

  Ledger({
    required this.id,
    required this.name,
    required this.interestRate,
    this.warningLimitPercent = 2.0,
    this.warningLimitOverride,
    List<LedgerParameter>? parameters,
    Map<String, String>? formulas,
    LedgerRules? rules,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : parameters = parameters ?? [],
        formulas = formulas ?? {},
        rules = rules ?? LedgerRules(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 兼容旧字段 warningLimit
  double? get warningLimit => warningLimitOverride;
  set warningLimit(double? v) {
    warningLimitOverride = v;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'interest_rate': interestRate,
        'warning_limit_percent': warningLimitPercent,
        'warning_limit_override': warningLimitOverride,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        'formulas': formulas,
        'rules': rules.toJson(),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Ledger.fromJson(Map<String, dynamic> j) => Ledger(
        id: j['id'] as String,
        name: j['name'] as String,
        interestRate: (j['interest_rate'] as num).toDouble(),
        warningLimitPercent: (j['warning_limit_percent'] as num?)?.toDouble() ?? 2.0,
        warningLimitOverride: (j['warning_limit_override'] as num?)?.toDouble() ??
            (j['warning_limit'] as num?)?.toDouble(),
        parameters: ((j['parameters'] as List?) ?? [])
            .map((e) => LedgerParameter.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        formulas: ((j['formulas'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        rules: j['rules'] != null
            ? LedgerRules.fromJson(Map<String, dynamic>.from(j['rules'] as Map))
            : LedgerRules(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updated_at'] as int),
      );
}

/// 内存中聚合的账本视图（账本 + 账单 + 最新结算）
class LedgerView {
  final Ledger ledger;
  final List<Bill> bills;
  Settlement? latestSettlement;
  final List<Settlement> settlementHistory;
  final bool mnemonicEnabled;  // 全局助记词是否已启用
  final bool unlocked;         // 全局助记词是否已解锁

  LedgerView({
    required this.ledger,
    required this.bills,
    this.latestSettlement,
    this.settlementHistory = const [],
    this.mnemonicEnabled = false,
    this.unlocked = true,
  });

  /// 账单合计金额（所有账单所有格子之和）
  /// 解锁后用内存中的解密值；未解锁返回 NaN
  double totalAmount() {
    if (mnemonicEnabled && !unlocked) return double.nan;
    double sum = 0;
    for (final b in bills) {
      sum += b.totalAmount;
    }
    return sum;
  }

  /// 应结金额（按 interestRate% 计息）：sum * (1 + rate/100)
  double expectedAmount() {
    final t = totalAmount();
    if (t.isNaN) return double.nan;
    return t * (1 + ledger.interestRate / 100.0);
  }

  /// 自动预警限额（按 warningLimitPercent% 动态计算，不写死）
  double autoWarningLimit() {
    final t = totalAmount();
    if (t.isNaN) return 0;
    return t * ledger.warningLimitPercent / 100.0;
  }

  /// 实际预警限额（手动覆盖优先，否则自动计算）
  double effectiveWarningLimit() {
    if (ledger.warningLimitOverride != null) return ledger.warningLimitOverride!;
    return autoWarningLimit();
  }

  /// 所有格子数量
  int get totalCellCount => bills.fold<int>(0, (sum, b) => sum + b.cells.length);
}
