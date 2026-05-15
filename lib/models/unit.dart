/// 支持的单位类型及换算规则
class ParameterUnit {
  static const String none = '';       // 无单位，数值不变
  static const String percent = '%';   // 百分比，数值 / 100
  static const String permille = '‰';  // 千分比，数值 / 1000
  static const String times = '倍';     // 倍数，数值不变
  static const String yuan = '元';      // 元，数值不变
  static const String piece = '个';     // 个，数值不变
  static const String time = '次';      // 次，数值不变

  /// 所有可选单位列表
  static const List<String> all = [none, percent, permille, times, yuan, piece, time];

  /// 获取单位的换算系数（公式计算时用）
  static double getFactor(String unit) {
    switch (unit) {
      case percent:
        return 0.01;    // % → 除以100
      case permille:
        return 0.001;   // ‰ → 除以1000
      case times:
      case yuan:
      case piece:
      case time:
      case none:
      default:
        return 1.0;     // 其他单位数值不变
    }
  }

  /// 获取显示标签
  static String getLabel(String unit) {
    switch (unit) {
      case percent:
        return '% (百分比)';
      case permille:
        return '‰ (千分比)';
      case times:
        return '倍 (倍数)';
      case yuan:
        return '元 (货币)';
      case piece:
        return '个 (数量)';
      case time:
        return '次 (次数)';
      case none:
      default:
        return '- 无单位';
    }
  }
}
