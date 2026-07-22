import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'gemini_service.dart';
import 'models.dart';
import 'storage_service.dart';

class HealthHome extends StatefulWidget {
  const HealthHome({
    super.key,
    required this.initialLanguage,
    required this.onLanguageChanged,
  });

  final String initialLanguage;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<HealthHome> createState() => _HealthHomeState();
}

class _HealthHomeState extends State<HealthHome> {
  static const _secureStorage = FlutterSecureStorage();
  final _gemini = GeminiService();
  final _storage = StorageService();
  final _picker = ImagePicker();
  final _input = TextEditingController();

  final List<HealthRecord> _records = [];
  final List<ErrorLogEntry> _logs = [];
  final List<ChatEntry> _messages = [];
  final List<GeminiAttachment> _attachments = [];

  HealthProfile _profile = const HealthProfile();
  bool _busy = false;
  int _tab = 0;
  late String _language;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await _storage.load();
    if (!mounted) return;
    setState(() {
      _records
        ..clear()
        ..addAll(state.records);
      _logs
        ..clear()
        ..addAll(state.logs);
      _profile = state.profile;
    });
  }

  Future<void> _save() => _storage.save(records: _records, profile: _profile, logs: _logs);

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String get _responseLanguage => switch (_language) {
        'en' => 'English',
        'ja' => 'Japanese',
        'zh' => 'Simplified Chinese',
        _ => 'Korean',
      };

  Future<void> _addPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1800);
    for (final file in files.take(5 - _attachments.length)) {
      _attachments.add(GeminiAttachment(
        bytes: await file.readAsBytes(),
        mimeType: 'image/jpeg',
        name: file.name,
      ));
    }
    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1800);
    if (file == null) return;
    _attachments.add(GeminiAttachment(
      bytes: await file.readAsBytes(),
      mimeType: 'image/jpeg',
      name: file.name,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _addDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'csv', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      if (_attachments.any((a) => RecordDeduplicator.sameDocumentBytes(a.bytes, bytes))) continue;
      _attachments.add(GeminiAttachment(
        bytes: bytes,
        mimeType: _mime(file.extension),
        name: file.name,
      ));
    }
    if (mounted) setState(() {});
  }

  String _mime(String? ext) => switch (ext?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  Set<String> _normalizedMedicationNames(Iterable<String> values) => values
      .map(RecordDeduplicator.normalize)
      .where((e) => e.isNotEmpty)
      .toSet();

  List<String> _findDuplicateMedications(Map<String, dynamic> update) {
    final incoming = (update['medications'] as List<dynamic>? ?? const []).map((e) => e.toString());
    final existingKeys = _normalizedMedicationNames(_profile.medications);
    return incoming.where((name) => existingKeys.contains(RecordDeduplicator.normalize(name))).toList();
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final key = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (key.isEmpty) {
      setState(() => _tab = 2);
      _snack('설정에서 Gemini API 키를 입력하세요.');
      return;
    }

    final userText = text.isEmpty ? '첨부한 처방전 또는 건강 문서를 분석해줘.' : text;
    setState(() {
      _messages.add(ChatEntry(role: 'user', text: userText));
      _busy = true;
      _input.clear();
    });

    try {
      final result = await _gemini.analyze(
        apiKey: key,
        userText: userText,
        attachments: List<GeminiAttachment>.from(_attachments),
        profile: _profile,
        responseLanguage: _responseLanguage,
      );
      final duplicates = _findDuplicateMedications(result.profileUpdate);
      final warning = duplicates.isEmpty
          ? ''
          : '⚠️ 중복 처방 가능성\n기존 복용약과 겹칠 수 있는 약: ${duplicates.join(', ')}\n의사 또는 약사에게 확인하기 전 임의로 함께 복용하거나 중단하지 마세요.\n\n';
      final answer = '$warning${result.answer}${result.followUpQuestion.isEmpty ? '' : '\n\n확인 질문: ${result.followUpQuestion}'}';

      final incoming = <HealthRecord>[];
      for (var i = 0; i < result.records.length; i++) {
        final item = result.records[i];
        incoming.add(HealthRecord(
          id: '${DateTime.now().microsecondsSinceEpoch}$i',
          category: item['category']?.toString() ?? 'other',
          title: item['title']?.toString() ?? '건강 기록',
          summary: item['summary']?.toString() ?? '',
          details: Map<String, dynamic>.from((item['details'] as Map?) ?? const {}),
          createdAt: DateTime.now(),
          inputMethod: _attachments.isEmpty ? 'chat' : 'attachment',
          confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
          sourceText: userText,
        ));
      }
      final unique = RecordDeduplicator.uniqueNewRecords(existing: _records, incoming: incoming);

      if (!mounted) return;
      setState(() {
        _messages.add(ChatEntry(role: 'assistant', text: answer));
        _records.insertAll(0, unique);
        _profile = _profile.merged(result.profileUpdate);
        _attachments.clear();
      });
      await _save();

      if (duplicates.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 44),
            title: const Text('중복 처방 가능성'),
            content: Text('기존 복용약과 겹칠 수 있습니다:\n${duplicates.join(', ')}\n\n처방한 의료진 또는 약사에게 반드시 확인하세요.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
          ),
        );
      }
      _snack(unique.length == incoming.length
          ? '${unique.length}건을 저장했습니다.'
          : '${unique.length}건 저장, 중복 ${incoming.length - unique.length}건 제외했습니다.');
    } on TimeoutException {
      _snack('분석 시간이 초과되었습니다. 다시 시도해 주세요.');
    } catch (error) {
      _logs.insert(0, ErrorLogEntry(time: DateTime.now(), stage: 'gemini', message: error.toString()));
      await _save();
      _snack('분석 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editApiKey() async {
    final controller = TextEditingController(text: await _secureStorage.read(key: 'gemini_api_key') ?? '');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gemini API 키'),
        content: TextField(controller: controller, obscureText: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              await _secureStorage.write(key: 'gemini_api_key', value: controller.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _chat() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return Align(
                  alignment: m.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(13),
                    constraints: const BoxConstraints(maxWidth: 620),
                    decoration: BoxDecoration(
                      color: m.role == 'user' ? const Color(0xFFDDF3E4) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(m.text),
                  ),
                );
              },
            ),
          ),
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => InputChip(
                  label: Text(_attachments[i].name),
                  onDeleted: () => setState(() => _attachments.removeAt(i)),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.attach_file),
                    onSelected: (value) {
                      if (value == 'camera') _takePhoto();
                      if (value == 'gallery') _addPhotos();
                      if (value == 'document') _addDocuments();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'camera', child: Text('사진 촬영')),
                      PopupMenuItem(value: 'gallery', child: Text('사진 선택')),
                      PopupMenuItem(value: 'document', child: Text('PDF·문서 선택')),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: '증상, 약, 식사 또는 질문을 입력하세요', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _busy ? null : _send, icon: _busy ? const CircularProgressIndicator() : const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _recordsView() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: const Color(0xFFFFECEC),
            child: const ListTile(
              leading: Icon(Icons.health_and_safety, color: Colors.red),
              title: Text('중복 처방 자동 경고', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('새 처방을 기존 복용약과 비교하고, 동일 약 또는 동일 성분 가능성을 경고합니다.'),
            ),
          ),
          const SizedBox(height: 8),
          ..._records.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(title: Text(r.title), subtitle: Text(r.summary), trailing: Text('${r.createdAt.month}/${r.createdAt.day}')),
              )),
        ],
      );

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(child: ListTile(leading: const Icon(Icons.key), title: const Text('Gemini API 키'), onTap: _editApiKey)),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('응답 언어'),
              trailing: DropdownButton<String>(
                value: _language,
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('시스템')),
                  DropdownMenuItem(value: 'ko', child: Text('한국어')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'ja', child: Text('日本語')),
                  DropdownMenuItem(value: 'zh', child: Text('中文')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _language = value);
                  widget.onLanguageChanged(value);
                },
              ),
            ),
          ),
          Card(child: ListTile(leading: const Icon(Icons.medication), title: const Text('저장된 복용약'), subtitle: Text(_profile.medications.isEmpty ? '없음' : _profile.medications.join(', ')))),
          Card(child: ListTile(leading: const Icon(Icons.bug_report), title: const Text('오류 로그'), subtitle: Text('${_logs.length}건'))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final pages = [_chat(), _recordsView(), _settings()];
    return Scaffold(
      appBar: AppBar(title: const Text('AI 건강비서')),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '대화'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '기록'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '설정'),
        ],
      ),
    );
  }
}
