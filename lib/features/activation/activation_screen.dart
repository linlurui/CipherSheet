import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _tokenCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _activate() async {
    final state = context.read<AppState>();
    final raw = _tokenCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请输入或粘贴授权 Token');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await state.activateWithToken(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  /// 选文件（桌面/Web）/选图片（移动端）→ 读取文本内容到 Token 输入框
  Future<void> _loadFromFile() async {
    try {
      final isMobile = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择授权 Token 文件',
        type: isMobile ? FileType.image : FileType.any,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final pf = result.files.first;
      String content;
      if (pf.bytes != null) {
        content = String.fromCharCodes(pf.bytes!);
      } else if (pf.path != null) {
        content = await File(pf.path!).readAsString();
      } else {
        setState(() => _error = '无法读取所选文件');
        return;
      }
      if (!mounted) return;
      setState(() {
        _tokenCtrl.text = content.trim();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '读取失败: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      child: const Icon(Icons.lock_outline,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text('CipherSheet',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('离线加密账本',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 28),

                TextField(
                  controller: _tokenCtrl,
                  maxLines: 6,
                  enableInteractiveSelection: true,
                  decoration: InputDecoration(
                    hintText: '-----BEGIN ENCRYPTED TOKEN-----\n...\n-----END ENCRYPTED TOKEN-----',
                    suffixIcon: IconButton(
                      tooltip: '粘贴',
                      icon: const Icon(Icons.content_paste),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null && data!.text!.isNotEmpty) {
                          _tokenCtrl.text = data.text!;
                        }
                      },
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _loadFromFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('从文件读取'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _busy ? null : _activate,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('激活'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _Tip(),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: const Text(
        '提示：\n'
        '• 请粘贴或导入你的激活码。',
        style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.6),
      ),
    );
  }
}
