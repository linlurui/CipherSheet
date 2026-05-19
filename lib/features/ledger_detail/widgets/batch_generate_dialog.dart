import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BatchGenerateDialog extends StatefulWidget {
  const BatchGenerateDialog({super.key});

  @override
  State<BatchGenerateDialog> createState() => _BatchGenerateDialogState();
}

class _BatchGenerateDialogState extends State<BatchGenerateDialog> {
  final _ctrl = TextEditingController(text: '49');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('一键批量生成账单'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('将按当前最大序号 +1 继续编号 (01, 02, ...)。',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '生成数量'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(_ctrl.text.trim()) ?? 0;
            if (n <= 0 || n > 999) return;
            Navigator.pop(context, n);
          },
          child: const Text('生成'),
        ),
      ],
    );
  }
}
