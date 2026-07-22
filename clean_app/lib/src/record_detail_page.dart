import 'dart:convert';

import 'package:flutter/material.dart';

import 'models.dart';

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({
    super.key,
    required this.record,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.onDelete,
  });

  final HealthRecord record;
  final String categoryLabel;
  final IconData categoryIcon;
  final Future<void> Function() onDelete;

  String _prettyValue(dynamic value) {
    if (value is List) return value.join(', ');
    if (value is Map) return const JsonEncoder.withIndent('  ').convert(value);
    return value?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(categoryLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFE7F4EA),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(categoryIcon, size: 38, color: const Color(0xFF176F46)),
                  const SizedBox(height: 12),
                  Text(record.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(record.summary, style: const TextStyle(fontSize: 17, height: 1.5)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('상세 정보', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (record.details.isEmpty)
                    const Text('추가 상세 정보가 없습니다.')
                  else
                    ...record.details.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Expanded(child: Text(_prettyValue(entry.value))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('기록 정보', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text('입력 방식: ${record.inputMethod}'),
                  Text('AI 신뢰도: ${(record.confidence * 100).round()}%'),
                  Text('저장 시각: ${record.createdAt.toLocal()}'),
                ],
              ),
            ),
          ),
          if (record.sourceText.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: ExpansionTile(
                title: const Text('원본 입력 보기'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(record.sourceText),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('기록 삭제'),
                      content: const Text('이 기록을 삭제하시겠습니까?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('취소'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!confirmed) return;
              await onDelete();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('기록 삭제'),
          ),
        ],
      ),
    );
  }
}
