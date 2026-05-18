import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/crypto/wordlist.dart';

/// 设置全局助记词（双模式：8词点选 / 16位密码）
class SetMnemonicDialog extends StatefulWidget {
  const SetMnemonicDialog({super.key});
  @override
  State<SetMnemonicDialog> createState() => _SetMnemonicDialogState();
}

class _SetMnemonicDialogState extends State<SetMnemonicDialog> {
  int _mode = 0; // 0: select, 1: word, 2: password
  String? _err;

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _mode == 0
          ? const Text('设置全局助记词')
          : _mode == 1
              ? const Text('8 词助记词')
              : const Text('16 位密码'),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 500 ? 400.0 : constraints.maxWidth * 0.9;
          return SizedBox(
            width: contentWidth,
            child: _mode == 0
            ? _buildModeSelect()
            : _mode == 1
                ? _buildWordMode()
                : _buildPasswordMode(),
          );
        },
      ),
      actions: _mode == 0
          ? [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
            ]
          : null,
    );
  }

  Widget _buildModeSelect() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '助记词将用于对所有账本金额进行二次加密 (PBKDF2 + AES-256-GCM)。\n'
          '遗失无法恢复！',
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('8 词点选'),
          subtitle: const Text('随机生成，简单易记'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            _generateWords();
            setState(() => _mode = 1);
          },
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('16 位密码'),
          subtitle: const Text('手动输入，安全性更高'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _mode = 2),
        ),
      ],
    );
  }

  Widget _buildWordMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '点击每个词确认选中，全部选中后提交。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        size: 12,
                        color: _selectedWords.contains(i)
                            ? Colors.green
                            : Colors.black26,
                      ),
                      const SizedBox(width: 3),
                      Text(_words[i],
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _selectedWords.contains(i)
                                ? Colors.green.shade900
                                : Colors.black87,
                          )),
                    ],
                  ),
                ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _generateWords,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重新生成', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _words.join(' ')));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('复制', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Text('${_selectedWords.length}/8',
                style: TextStyle(
                  fontSize: 12,
                  color: _selectedWords.length == 8 ? Colors.green : Colors.black45,
                )),
            const Spacer(),
            TextButton(
                onPressed: () => setState(() => _mode = 0),
                child: const Text('返回')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _selectedWords.length < 8
                  ? null
                  : () => Navigator.pop(context, _words.join(' ')),
              child: const Text('确认'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '至少 16 位，建议含大小写字母、数字和特殊符号。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            hintText: '至少 16 位，含特殊符号',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passConfirmCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '再次确认',
            isDense: true,
          ),
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
                onPressed: () => setState(() => _mode = 0),
                child: const Text('返回')),
            const Spacer(),
            FilledButton(
              onPressed: () {
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
                Navigator.pop(context, a);
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 解锁全局助记词（双模式：8词点选 / 16位密码）
class UnlockMnemonicDialog extends StatefulWidget {
  const UnlockMnemonicDialog({super.key});
  @override
  State<UnlockMnemonicDialog> createState() => _UnlockMnemonicDialogState();
}

class _UnlockMnemonicDialogState extends State<UnlockMnemonicDialog> {
  int _mode = 0; // 0: select, 1: word, 2: password
  String? _err;

  // 8词模式
  final _wordCtrl = TextEditingController();

  // 密码模式
  final _passCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _mode == 0
          ? const Text('解锁全局助记词')
          : _mode == 1
              ? const Text('输入 8 词助记词')
              : const Text('输入密码'),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 500 ? 360.0 : constraints.maxWidth * 0.9;
          return SizedBox(
            width: contentWidth,
            child: _mode == 0
                ? _buildModeSelect()
                : _mode == 1
                    ? _buildWordInput()
                    : _buildPasswordInput(),
          );
        },
      ),
      actions: _mode == 0
          ? [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
            ]
          : null,
    );
  }

  Widget _buildModeSelect() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '请选择您设置助记词时的方式来解锁。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('8 词助记词'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _mode = 1),
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('16 位密码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _mode = 2),
        ),
      ],
    );
  }

  Widget _buildWordInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '请输入您的 8 词助记词，以空格分隔。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _wordCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '8 词助记词',
            hintText: 'word1 word2 word3 ...',
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
                onPressed: () => setState(() => _mode = 0),
                child: const Text('返回')),
            const Spacer(),
            FilledButton(
              onPressed: () {
                final v = _wordCtrl.text.trim();
                if (v.isEmpty) {
                  setState(() => _err = '请输入助记词');
                  return;
                }
                Navigator.pop(context, v);
              },
              child: const Text('解锁'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '请输入您的 16 位密码。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '密码',
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        if (_err != null) ...[
          const SizedBox(height: 6),
          Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
                onPressed: () => setState(() => _mode = 0),
                child: const Text('返回')),
            const Spacer(),
            FilledButton(
              onPressed: () {
                final v = _passCtrl.text;
                if (v.isEmpty) {
                  setState(() => _err = '请输入密码');
                  return;
                }
                Navigator.pop(context, v);
              },
              child: const Text('解锁'),
            ),
          ],
        ),
      ],
    );
  }
}
