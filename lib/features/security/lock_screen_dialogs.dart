import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/security/screen_lock_service.dart';

/// 安全菜单对话框
class SecurityMenuDialog extends StatelessWidget {
  final bool mnemonicEnabled;
  final bool isUnlocked;
  final LockType lockType;
  final bool biometricEnabled;
  final Future<bool> Function() canUseBiometric;

  const SecurityMenuDialog({
    super.key,
    required this.mnemonicEnabled,
    required this.isUnlocked,
    required this.lockType,
    required this.biometricEnabled,
    required this.canUseBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.security, color: Colors.blue),
          SizedBox(width: 8),
          Text('安全中心'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 助记词选项
          ListTile(
            leading: Icon(
              mnemonicEnabled
                  ? (isUnlocked ? Icons.lock_open : Icons.lock_outline)
                  : Icons.key_outlined,
              color: mnemonicEnabled
                  ? (isUnlocked ? Colors.green : Colors.orange)
                  : Colors.grey,
            ),
            title: const Text('全局助记词'),
            subtitle: Text(
              mnemonicEnabled
                  ? (isUnlocked ? '已启用 · 已解锁' : '已启用 · 已锁定')
                  : '未设置 · 用于金额二次加密',
            ),
            onTap: () => Navigator.pop(context, 'mnemonic'),
          ),
          const Divider(),
          // 锁屏密码选项
          ListTile(
            leading: Icon(
              lockType == LockType.none ? Icons.screen_lock_portrait_outlined : Icons.screen_lock_portrait,
              color: lockType == LockType.none ? Colors.grey : Colors.blue,
            ),
            title: const Text('锁屏密码'),
            subtitle: Text(_lockTypeText()),
            trailing: lockType != LockType.none
                ? const Icon(Icons.chevron_right, size: 18)
                : null,
            onTap: () => Navigator.pop(context, 'lockscreen'),
          ),
          const Divider(),
          // 激活信息选项
          ListTile(
            leading: const Icon(Icons.shield_outlined, color: Colors.green),
            title: const Text('激活信息'),
            subtitle: const Text('查看授权状态和Token信息'),
            onTap: () => Navigator.pop(context, 'license'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  String _lockTypeText() {
    switch (lockType) {
      case LockType.none:
        return '未设置 · 支持6位密码、手势、生物识别';
      case LockType.pin6:
        return '已启用 · 6位数字密码';
      case LockType.pattern:
        return '已启用 · 手势密码';
      case LockType.biometric:
        return '已启用 · 生物识别';
    }
  }
}

/// 锁屏密码设置主对话框
class LockScreenSetupDialog extends StatefulWidget {
  final ScreenLockService service;

  const LockScreenSetupDialog({super.key, required this.service});

  @override
  State<LockScreenSetupDialog> createState() => _LockScreenSetupDialogState();
}

class _LockScreenSetupDialogState extends State<LockScreenSetupDialog> {
  bool _canUseBiometric = false;
  bool _hasPin = false;
  bool _hasPattern = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final canBio = await widget.service.canCheckBiometrics();
    setState(() {
      _canUseBiometric = canBio;
      _hasPin = widget.service.lockType == LockType.pin6;
      _hasPattern = widget.service.lockType == LockType.pattern;
      _biometricEnabled = widget.service.biometricEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('锁屏密码设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 6位数字密码
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('6位数字密码'),
              subtitle: Text(_hasPin ? '已设置 · 点击修改' : '未设置 · 点击设置'),
              trailing: _hasPin
                  ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                  : const Icon(Icons.chevron_right, size: 18),
              onTap: () => _setupPin6(),
            ),
            const Divider(),
            // 手势密码
            ListTile(
              leading: const Icon(Icons.gesture),
              title: const Text('手势密码'),
              subtitle: Text(_hasPattern ? '已设置 · 点击修改' : '未设置 · 点击设置'),
              trailing: _hasPattern
                  ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                  : const Icon(Icons.chevron_right, size: 18),
              onTap: () => _setupPattern(),
            ),
            const Divider(),
            // 生物识别开关
            if (_canUseBiometric) ...[
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('生物识别'),
                subtitle: const Text('使用指纹或面容快速解锁'),
                value: _biometricEnabled,
                onChanged: (v) => _toggleBiometric(v),
              ),
              const Divider(),
            ],
            // 清除所有
            if (_hasPin || _hasPattern || _biometricEnabled)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('清除所有锁屏', style: TextStyle(color: Colors.red)),
                onTap: () => _confirmClear(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _setupPin6() async {
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Pin6SetupDialog(
        title: _hasPin ? '修改6位密码' : '设置6位密码',
        requireConfirm: true,
      ),
    );
    if (pin != null && pin.length == 6) {
      final ok = await widget.service.setPin6(pin);
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '6位密码已设置' : '设置失败')),
        );
      }
    }
  }

  Future<void> _setupPattern() async {
    final pattern = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PatternSetupDialog(
        title: _hasPattern ? '修改手势密码' : '设置手势密码',
      ),
    );
    if (pattern != null && pattern.length >= 4) {
      final ok = await widget.service.setPattern(pattern);
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '手势密码已设置' : '设置失败')),
        );
      }
    }
  }

  Future<void> _toggleBiometric(bool enabled) async {
    final result = await widget.service.setBiometricEnabled(enabled);
    if (result) {
      setState(() => _biometricEnabled = enabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(enabled ? '生物识别已启用' : '生物识别已关闭')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生物识别设置失败，请检查系统设置')),
        );
      }
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除锁屏密码'),
        content: const Text('确定要清除所有锁屏密码设置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.service.clear();
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('锁屏密码已清除')),
        );
      }
    }
  }
}

/// 6位数字密码设置/验证对话框
class Pin6SetupDialog extends StatefulWidget {
  final String title;
  final bool requireConfirm;
  final bool isVerification;

  const Pin6SetupDialog({
    super.key,
    required this.title,
    this.requireConfirm = true,
    this.isVerification = false,
  });

  @override
  State<Pin6SetupDialog> createState() => _Pin6SetupDialogState();
}

class _Pin6SetupDialogState extends State<Pin6SetupDialog> {
  String _pin = '';
  String? _firstPin;
  String _error = '';

  void _onDigit(String d) {
    if (_pin.length < 6) {
      setState(() {
        _pin += d;
        _error = '';
      });
      if (_pin.length == 6) {
        _onComplete();
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  void _onComplete() {
    if (widget.isVerification) {
      Navigator.pop(context, _pin);
      return;
    }

    if (widget.requireConfirm) {
      if (_firstPin == null) {
        setState(() {
          _firstPin = _pin;
          _pin = '';
        });
      } else if (_pin == _firstPin) {
        Navigator.pop(context, _pin);
      } else {
        setState(() {
          _error = '两次输入不一致，请重新设置';
          _firstPin = null;
          _pin = '';
        });
      }
    } else {
      Navigator.pop(context, _pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _firstPin != null;
    return AlertDialog(
      title: Text(isConfirm ? '再次输入以确认' : widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 密码显示点
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  return Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? Colors.blue : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            // 数字键盘
            _buildKeypad(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        for (int row = 0; row < 3; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int col = 1; col <= 3; col++)
                _buildKey('${row * 3 + col}'),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 64, height: 56),
            _buildKey('0'),
            SizedBox(
              width: 64,
              height: 56,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined),
                onPressed: _onBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(String digit) {
    return SizedBox(
      width: 64,
      height: 56,
      child: TextButton(
        onPressed: () => _onDigit(digit),
        child: Text(digit, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

/// 手势密码设置/验证对话框
class PatternSetupDialog extends StatefulWidget {
  final String title;
  final bool isVerification;

  const PatternSetupDialog({
    super.key,
    required this.title,
    this.isVerification = false,
  });

  @override
  State<PatternSetupDialog> createState() => _PatternSetupDialogState();
}

class _PatternSetupDialogState extends State<PatternSetupDialog> {
  List<int> _pattern = [];
  List<int>? _firstPattern;
  String _error = '';
  Offset? _currentDragPos;
  final GlobalKey _gridKey = GlobalKey();
  static const double _gridSize = 260;
  static const double _dotRadius = 24;

  /// 根据坐标找到命中的点索引（0-8），未命中返回 null
  int? _hitTest(Offset localPos) {
    final cellSize = _gridSize / 3;
    for (int i = 0; i < 9; i++) {
      final row = i ~/ 3;
      final col = i % 3;
      final cx = col * cellSize + cellSize / 2;
      final cy = row * cellSize + cellSize / 2;
      final dx = localPos.dx - cx;
      final dy = localPos.dy - cy;
      if (dx * dx + dy * dy <= _dotRadius * _dotRadius) {
        return i;
      }
    }
    return null;
  }

  void _onDragUpdate(Offset localPos) {
    final idx = _hitTest(localPos);
    setState(() {
      _currentDragPos = localPos;
      if (idx != null && !_pattern.contains(idx)) {
        _pattern.add(idx);
        _error = '';
      }
    });
  }

  void _onDragEnd() {
    setState(() => _currentDragPos = null);
    if (_pattern.length > 0 && _pattern.length < 4) {
      setState(() {
        _error = '请至少连接4个点';
        _pattern = [];
      });
    }
  }

  void _onReset() {
    setState(() {
      _pattern = [];
      _error = '';
    });
  }

  void _onConfirm() {
    if (_pattern.length < 4) {
      setState(() => _error = '请至少连接4个点');
      return;
    }

    if (widget.isVerification) {
      Navigator.pop(context, _pattern);
      return;
    }

    if (_firstPattern == null) {
      setState(() {
        _firstPattern = List.from(_pattern);
        _pattern = [];
      });
    } else if (_listEquals(_pattern, _firstPattern!)) {
      Navigator.pop(context, _pattern);
    } else {
      setState(() {
        _error = '两次手势不一致，请重新设置';
        _firstPattern = null;
        _pattern = [];
      });
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _firstPattern != null;
    return AlertDialog(
      title: Text(isConfirm ? '请再次绘制以确认' : widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3x3 手势点阵（支持拖拽）
            Listener(
              key: _gridKey,
              onPointerDown: (e) {
                final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(e.position);
                setState(() {
                  _pattern = [];
                  _error = '';
                });
                _onDragUpdate(local);
              },
              onPointerMove: (e) {
                final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(e.position);
                _onDragUpdate(local);
              },
              onPointerUp: (_) => _onDragEnd(),
              onPointerCancel: (_) => _onDragEnd(),
              child: SizedBox(
                width: _gridSize,
                height: _gridSize,
                child: CustomPaint(
                  painter: _PatternPainter(
                    pattern: _pattern,
                    gridSize: _gridSize,
                    dotRadius: _dotRadius,
                    dragPos: _currentDragPos,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_pattern.isNotEmpty)
              Text('已连接 ${_pattern.length} 个点',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _onReset,
          child: const Text('重置'),
        ),
        FilledButton(
          onPressed: _pattern.length >= 4 ? _onConfirm : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

/// 手势密码绘制器
class _PatternPainter extends CustomPainter {
  final List<int> pattern;
  final double gridSize;
  final double dotRadius;
  final Offset? dragPos;

  _PatternPainter({
    required this.pattern,
    required this.gridSize,
    required this.dotRadius,
    this.dragPos,
  });

  Offset _centerOf(int index) {
    final cellSize = gridSize / 3;
    final row = index ~/ 3;
    final col = index % 3;
    return Offset(col * cellSize + cellSize / 2, row * cellSize + cellSize / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.6)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // 绘制连线
    for (int i = 0; i < pattern.length - 1; i++) {
      canvas.drawLine(_centerOf(pattern[i]), _centerOf(pattern[i + 1]), linePaint);
    }
    // 拖拽中：绘制最后一个点到当前位置的线
    if (pattern.isNotEmpty && dragPos != null) {
      canvas.drawLine(_centerOf(pattern.last), dragPos!, linePaint);
    }

    // 绘制 9 个点
    for (int i = 0; i < 9; i++) {
      final c = _centerOf(i);
      final selected = pattern.contains(i);
      final order = pattern.indexOf(i);

      // 外圈
      final bgPaint = Paint()
        ..color = selected ? Colors.blue : Colors.grey.shade300;
      canvas.drawCircle(c, dotRadius, bgPaint);

      // 边框
      if (selected) {
        final borderPaint = Paint()
          ..color = Colors.blue.shade700
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(c, dotRadius, borderPaint);

        // 序号
        final tp = TextPainter(
          text: TextSpan(
            text: '${order + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pattern != pattern || old.dragPos != dragPos;
}

/// 锁屏验证入口对话框
class LockScreenVerifyDialog extends StatefulWidget {
  final ScreenLockService service;

  const LockScreenVerifyDialog({super.key, required this.service});

  @override
  State<LockScreenVerifyDialog> createState() => _LockScreenVerifyDialogState();
}

class _LockScreenVerifyDialogState extends State<LockScreenVerifyDialog> {
  int _failedAttempts = 0;
  static const int _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    if (widget.service.biometricEnabled) {
      final result = await widget.service.authenticateBiometric();
      if (result && mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockType = widget.service.lockType;

    return AlertDialog(
      title: const Text('解锁应用'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock, size: 48, color: Colors.blue),
          const SizedBox(height: 16),
          if (lockType == LockType.pin6)
            _buildPin6Verify()
          else if (lockType == LockType.pattern)
            _buildPatternVerify()
          else
            const Text('请验证身份'),
          if (widget.service.biometricEnabled)
            TextButton.icon(
              onPressed: _tryBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('使用生物识别'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消（退出应用）'),
        ),
      ],
    );
  }

  Widget _buildPin6Verify() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('请输入6位数字密码'),
        const SizedBox(height: 8),
        SizedBox(
          width: 200,
          child: TextField(
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              counterText: '',
              hintText: '------',
            ),
            onChanged: (v) {
              if (v.length == 6) {
                _verifyPin6(v);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPatternVerify() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('请绘制手势密码'),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () async {
            final pattern = await showDialog<List<int>>(
              context: context,
              builder: (ctx) => const PatternSetupDialog(
                title: '验证手势',
                isVerification: true,
              ),
            );
            if (pattern != null) {
              _verifyPattern(pattern);
            }
          },
          child: const Text('绘制手势'),
        ),
      ],
    );
  }

  void _verifyPin6(String pin) {
    if (widget.service.verifyPin6(pin)) {
      Navigator.pop(context, true);
    } else {
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        Navigator.pop(context, false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('密码错误，还剩 ${_maxAttempts - _failedAttempts} 次机会')),
        );
      }
    }
  }

  void _verifyPattern(List<int> pattern) {
    if (widget.service.verifyPattern(pattern)) {
      Navigator.pop(context, true);
    } else {
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        Navigator.pop(context, false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('手势错误，还剩 ${_maxAttempts - _failedAttempts} 次机会')),
        );
      }
    }
  }
}
