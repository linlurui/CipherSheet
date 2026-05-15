import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/wordlist.dart';
import '../../state/app_state.dart';

/// 激活后助记词向导 —— 双模式：8词点选 或 16位手输密码
class MnemonicWizardScreen extends StatefulWidget {
  const MnemonicWizardScreen({super.key});

  @override
  State<MnemonicWizardScreen> createState() => _MnemonicWizardScreenState();
}

class _MnemonicWizardScreenState extends State<MnemonicWizardScreen> {
  String? _err;
  bool _busy = false;
  int _step = 0; // 0: intro, 1: mode select, 2: word mode, 3: password mode, 4: done

  // 8词模式
  List<String> _words = const [];
  final Set<int> _selectedWords = {};

  // 密码模式
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _generateWords();
  }

  void _generateWords() {
    final rng = Random.secure();
    final words = List<String>.generate(
      8,
      (_) => mnemonicWordlist[rng.nextInt(mnemonicWordlist.length)],
    );
    setState(() {
      _words = words;
      _selectedWords.clear();
      _err = null;
    });
  }

  String get _mnemonicText => _words.join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 0) _buildIntro(),
                  if (_step == 1) _buildModeSelect(),
                  if (_step == 2) _buildWordMode(),
                  if (_step == 3) _buildPasswordMode(),
                  if (_step == 4) _buildDone(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('安全设置向导',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('激活成功！接下来建议您：',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              SizedBox(height: 10),
              Text('• 设置全局助记词，对所有账本金额进行二次加密',
                  style: TextStyle(height: 1.6)),
              Text('• 助记词同时注册为恢复通道，方便跨设备恢复',
                  style: TextStyle(height: 1.6)),
              Text('• 遗失助记词将导致加密金额永久不可读',
                  style: TextStyle(height: 1.6, color: Colors.red)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => setState(() => _step = 1),
          icon: const Icon(Icons.key),
          label: const Text('设置助记词'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            context.read<AppState>().dismissMnemonicWizard();
          },
          child: const Text('跳过，稍后设置'),
        ),
      ],
    );
  }

  Widget _buildModeSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back),
            ),
            const Text('选择加密方式',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 16),
        _ModeCard(
          icon: Icons.text_fields,
          title: '8 词点选',
          desc: '系统随机生成 8 个短词，点击确认即可。简单易记，适合日常使用。',
          onTap: () {
            _generateWords();
            setState(() => _step = 2);
          },
        ),
        const SizedBox(height: 12),
        _ModeCard(
          icon: Icons.password,
          title: '16 位密码',
          desc: '手动输入至少 16 位密码（含特殊符号）。安全性更高，适合专业用户。',
          onTap: () => setState(() => _step = 3),
        ),
      ],
    );
  }

  Widget _buildWordMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _step = 1),
              icon: const Icon(Icons.arrow_back),
            ),
            const Text('8 词助记词',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '点击每个词确认选中，全部选中后即可提交。请抄写保管，遗失无法恢复！',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _words.length; i++)
                InkWell(
                  onTap: () => setState(() {
                    if (_selectedWords.contains(i)) {
                      _selectedWords.remove(i);
                    } else {
                      _selectedWords.add(i);
                    }
                  }),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _selectedWords.contains(i)
                          ? Colors.green.shade50
                          : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _selectedWords.contains(i)
                            ? Colors.green
                            : Colors.black12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedWords.contains(i)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 14,
                          color: _selectedWords.contains(i)
                              ? Colors.green
                              : Colors.black26,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _words[i],
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _selectedWords.contains(i)
                                ? Colors.green.shade900
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _mnemonicText));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('助记词已复制到剪贴板'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _generateWords,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新生成'),
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Text('${_selectedWords.length}/8 已确认',
                style: TextStyle(
                  color: _selectedWords.length == 8
                      ? Colors.green
                      : Colors.black45,
                )),
            const Spacer(),
            FilledButton(
              onPressed: (_busy || _selectedWords.length < 8) ? null : _submitWords,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('确认设置'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _step = 1),
              icon: const Icon(Icons.arrow_back),
            ),
            const Text('16 位密码',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '请输入至少 16 位密码（建议包含大小写字母、数字和特殊符号）。\n'
          '此密码将作为全局助记词，对所有账本金额进行二次加密。',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            hintText: '至少 16 位，含特殊符号',
            helperText: '例如: Kx#9mP!vL2@qR4nW',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passConfirmCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: '再次确认'),
        ),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _submitPassword,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('确认设置'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle, size: 64, color: Colors.green.shade600),
        const SizedBox(height: 16),
        const Text('助记词设置成功！',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('全局助记词已启用，所有账本金额已二次加密。',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            context.read<AppState>().dismissMnemonicWizard();
          },
          child: const Text('开始使用'),
        ),
      ],
    );
  }

  Future<void> _submitWords() async {
    if (_selectedWords.length < 8) return;
    setState(() { _busy = true; _err = null; });
    final err = await context.read<AppState>().setMnemonic(_mnemonicText);
    if (!mounted) return;
    if (err != null) {
      setState(() { _busy = false; _err = err; });
    } else {
      setState(() { _busy = false; _step = 4; });
    }
  }

  Future<void> _submitPassword() async {
    final a = _passCtrl.text;
    final b = _passConfirmCtrl.text;
    if (a.length < 16) {
      setState(() => _err = '密码至少 16 位');
      return;
    }
    if (a != b) {
      setState(() => _err = '两次输入不一致');
      return;
    }
    setState(() { _busy = true; _err = null; });
    final err = await context.read<AppState>().setMnemonic(a);
    if (!mounted) return;
    if (err != null) {
      setState(() { _busy = false; _err = err; });
    } else {
      setState(() { _busy = false; _step = 4; });
    }
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(desc,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54, height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
