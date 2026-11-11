import 'package:flutter/material.dart';

class AddTaskDialog extends StatefulWidget {
  const AddTaskDialog({super.key});

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _concurrencyController = TextEditingController(text: '8');

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _concurrencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增下载'),
      scrollable: true,
      content: const Text('此功能待 FFmpeg 集成后启用'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: const Text('开始下载'),
        ),
      ],
    );
  }
}