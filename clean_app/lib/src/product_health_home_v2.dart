import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_services.dart';
import 'gemini_service.dart';
import 'models.dart';
import 'storage_service.dart';

class ProductHealthHomeV2 extends StatefulWidget {
  const ProductHealthHomeV2({
    super.key,
    required this.initialLanguage,
    required this.onLanguageChanged,
  });

  final String initialLanguage;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<ProductHealthHomeV2> createState() => _ProductHealthHomeV2State();
}

class _ProductHealthHomeV2State extends State<ProductHealthHomeV2> {
  static const _secureStorage = FlutterSecureStorage();
  final _storage = StorageService();
  final _gemini = GeminiService();
  final _picker = ImagePicker();
  final _speech = SpeechService();
  final _permissions = PermissionService();
  final _prefs = AppPreferences();
  final _input = TextEditingController();

  final List<HealthRecord> _records = <HealthRecord>[];
  final List<ErrorLogEntry> _logs = <ErrorLogEntry>[];
  final List<ChatEntry> _messages = <ChatEntry>[];
  final List<GeminiAttachment> _attachments = <GeminiAttachment>[];

  HealthProfile _profile = const HealthProfile();
  PermissionSnapshot? _permissionSnapshot;
  late String _language;
  int _tab = 0;
  bool _busy = false;
  bool _listening = false;
  bool _notificationsEnabled = true;
  bool _backgroundEnabled = true;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _initialize();
  }

  Future<void> _initialize() async {
    await NotificationService.instance.initialize();
    final state = await _storage.load();
    final snapshot = await _permissions.inspect();
    final notifications = await _prefs.notificationsEnabled;
    final background = await _prefs.backgroundEnabled;
    if (!mounted) return;
    setState(() {
      _records
        ..clear()
        ..addAll(state.records);
      _logs
        ..clear()
        ..addAll(state.logs);
      _profile = state.profile;
      _permissionSnapshot = snapshot;
      _notificationsEnabled = notifications;
      _backgroundEnabled = background;
    });
    if (!await _prefs.onboardingCompleted && mounted) {
      await _showOnboarding();
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _input.dispose();
    super.dispose();
  }

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

  Future<void> _showOnboarding() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.health_and_safety_outlined, size: 48),
        title: const Text('AI 건강비서 시작하기'),
        content: const Text(
          '사진 분석, 음성 입력, 알림과 일정 관리를 위해 필요한 권한을 설정합니다. '
          '권한은 설정 메뉴에서 언제든 변경할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _prefs.setOnboardingCompleted(true);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () async {
              _permissionSnapshot = await _permissions.requestEssential();
              await _prefs.setOnboardingCompleted(true);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) setState(() {});
            },
            child: const Text('권한 설정'),
          ),
        ],
      ),
    );
  }

  Future<void> _takePhoto() async {
    final granted = await Permission.camera.request().isGranted;
    if (!granted) {
      _snack('카메라 권한이 필요합니다.');
      return;
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 2000,
    );
    if (file == null) return;
    _attachments.add(
      GeminiAttachment(
        bytes: await file.readAsBytes(),
        mimeType: 'image/jpeg',
        name: file.name,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 82, maxWidth: 2000);
    final room = 5 - _attachments.length;
    if (room <= 0) {
      _snack('사진은 최대 5장까지 첨부할 수 있습니다.');
      return;
    }
    for (final file in files.take(room)) {
      _attachments.add(
        GeminiAttachment(
          bytes: await file.readAsBytes(),
          mimeType: 'image/jpeg',
          name: file.name,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _addDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'pdf',
        'txt',
        'csv',
        'jpg',
        'jpeg',
        'png',
        'webp',
      ],
    );
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final duplicate = _attachments.any(
        (item) => RecordDeduplicator.sameDocumentBytes(item.bytes, bytes),
      );
      if (duplicate) continue;
      final extension = file.extension?.toLowerCase();
      final mime = switch (extension) {
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      _attachments.add(
        GeminiAttachment(bytes: bytes, mimeType: mime, name: file.name),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeech() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final granted = await Permission.microphone.request().isGranted;
    if (!granted) {
      _snack('마이크 권한이 필요합니다.');
      return;
    }
    final started = await _speech.start(
      onText: (text) {
        _input.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      },
    );
    if (mounted) setState(() => _listening = started);
    if (!started) _snack('음성 인식을 시작할 수 없습니다.');
  }

  Future<void> _saveState() => _storage.save(
        records: _records,
        profile: _profile,
        logs: _logs,
      );

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final key = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (key.isEmpty) {
      setState(() => _tab = 3);
      _snack('설정에서 Gemini API 키를 입력하세요.');
      return;
    }
    final userText = text.isEmpty
        ? '첨부한 건강 문서를 분석하고 저장할 내용을 정리해줘.'
        : text;
    setState(() {
      _messages.add(ChatEntry(role: 'user', text: userText));
      _input.clear();
      _busy = true;
    });
    try {
      final result = await _gemini.analyze(
        apiKey: key,
        userText: userText,
        attachments: List<GeminiAttachment>.from(_attachments),
        profile: _profile,
        responseLanguage: _responseLanguage,
      );
      final incoming = <HealthRecord>[];
      for (var index = 0; index < result.records.length; index++) {
        final item = result.records[index];
        incoming.add(
          HealthRecord(
            id: '${DateTime.now().microsecondsSinceEpoch}$index',
            category: item['category']?.toString() ?? 'other',
            title: item['title']?.toString() ?? '건강 기록',
            summary: item['summary']?.toString() ?? '',
            details: Map<String, dynamic>.from(
              (item['details'] as Map?) ?? const <String, dynamic>{},
            ),
            createdAt: DateTime.now(),
            inputMethod: _attachments.isEmpty ? 'chat' : 'attachment',
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            sourceText: userText,
          ),
        );
      }
      final unique = RecordDeduplicator.uniqueNewRecords(
        existing: _records,
        incoming: incoming,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatEntry(
            role: 'assistant',
            text: '${result.answer}'
                '${result.followUpQuestion.isEmpty ? '' : '\n\n확인 질문: ${result.followUpQuestion}'}',
          ),
        );
        _records.insertAll(0, unique);
        _profile = _profile.merged(result.profileUpdate);
        _attachments.clear();
      });
      await _saveState();
      _snack('${unique.length}건을 저장했습니다.');
    } on TimeoutException {
      _snack('분석 시간이 초과되었습니다.');
    } catch (error) {
      _logs.insert(
        0,
        ErrorLogEntry(
          time: DateTime.now(),
          stage: 'gemini',
          message: error.toString(),
        ),
      );
      await _saveState();
      _snack('분석 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editApiKey() async {
    final controller = TextEditingController(
      text: await _secureStorage.read(key: 'gemini_api_key') ?? '',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gemini API 키'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              await _secureStorage.write(
                key: 'gemini_api_key',
                value: controller.text.trim(),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _snack('API 키를 저장했습니다.');
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _testApi() async {
    final key = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (key.isEmpty) {
      _snack('API 키를 먼저 입력하세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _gemini.analyze(
        apiKey: key,
        userText: '연결 테스트입니다. 확인이라고 짧게 답하세요.',
        attachments: const <GeminiAttachment>[],
        profile: const HealthProfile(),
        responseLanguage: 'Korean',
      );
      _snack('Gemini 연결이 정상입니다.');
    } catch (_) {
      _snack('Gemini 연결에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleMedicationReminder() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (time == null) return;
    await NotificationService.instance.scheduleDaily(
      id: 1001,
      title: '복약 알림',
      body: '복용 중인 약을 확인할 시간입니다.',
      hour: time.hour,
      minute: time.minute,
    );
    if (!mounted) return;
    _snack('매일 ${time.format(context)}에 알림을 설정했습니다.');
  }

  Future<void> _openCalendar() async {
    final uri = Uri.parse('https://calendar.google.com/calendar/u/0/r');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _snack('캘린더를 열 수 없습니다.');
  }

  Future<void> _confirmReset() async {
    final controller = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 44),
        title: const Text('건강 데이터 초기화'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('저장 기록, 건강 프로필과 오류 로그가 삭제되며 복구할 수 없습니다.'),
            const SizedBox(height: 12),
            const Text('계속하려면 초기화를 입력하세요.'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim() == '초기화',
            ),
            child: const Text('최종 삭제'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (approved != true) {
      _snack('초기화가 취소되었습니다.');
      return;
    }
    await _storage.clearHealthData();
    await NotificationService.instance.cancelAll();
    if (!mounted) return;
    setState(() {
      _records.clear();
      _logs.clear();
      _messages.clear();
      _attachments.clear();
      _profile = const HealthProfile();
    });
    _snack('건강 데이터가 초기화되었습니다.');
  }

  Widget _chatPage() => Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '증상, 약, 식사, 처방전 또는 검사결과를 알려주세요.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      final message = _messages[index];
                      return Align(
                        alignment: message.role == 'user'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(13),
                          constraints: const BoxConstraints(maxWidth: 620),
                          decoration: BoxDecoration(
                            color: message.role == 'user'
                                ? const Color(0xFFDDF3E4)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(message.text),
                        ),
                      );
                    },
                  ),
          ),
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, index) => InputChip(
                  label: Text(_attachments[index].name),
                  onDeleted: () => setState(() => _attachments.removeAt(index)),
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
                  IconButton(
                    tooltip: '음성 입력',
                    onPressed: _toggleSpeech,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '건강 내용을 입력하세요',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _healthCard(String title, IconData icon, List<String> items) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text('등록된 정보가 없습니다.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items.map((item) => Chip(label: Text(item))).toList(),
                ),
            ],
          ),
        ),
      );

  Widget _healthPage() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _healthCard(
            '확정 질환',
            Icons.verified_outlined,
            _profile.confirmedConditions,
          ),
          _healthCard(
            'AI 추정 질환',
            Icons.help_outline,
            _profile.inferredConditions,
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: const Icon(Icons.medication_outlined),
              title: const Text('복용 중인 약'),
              subtitle: Text('${_profile.medications.length}종'),
              children: _profile.medications
                  .map(
                    (item) => ListTile(
                      leading: const Icon(Icons.circle, size: 8),
                      title: Text(item),
                    ),
                  )
                  .toList(),
            ),
          ),
          _healthCard(
            '알레르기',
            Icons.warning_amber_outlined,
            _profile.allergies,
          ),
          _healthCard('건강 메모', Icons.notes_outlined, _profile.notes),
        ],
      );

  Widget _recordsPage() => ListView(
        padding: const EdgeInsets.all(12),
        children: _records.isEmpty
            ? const [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('저장된 기록이 없습니다.'),
                  ),
                ),
              ]
            : _records
                .map(
                  (record) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      title: Text(record.title),
                      subtitle: Text(record.summary),
                      trailing: Text(
                        '${record.createdAt.month}/${record.createdAt.day}',
                      ),
                      children: [
                        if (record.details.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                record.details.entries
                                    .map((entry) => '${entry.key}: ${entry.value}')
                                    .join('\n'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
                .toList(),
      );

  String _permissionText(PermissionStatus status) {
    if (status.isGranted) return '허용';
    if (status.isLimited) return '일부 허용';
    if (status.isPermanentlyDenied) return '설정 필요';
    return '미허용';
  }

  Widget _settingsPage() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('AI 및 언어', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.key),
              title: const Text('Gemini API 키'),
              onTap: _editApiKey,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.network_check),
              title: const Text('Gemini 연결 테스트'),
              onTap: _testApi,
            ),
          ),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text('권한 및 시스템', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('권한 관리'),
              subtitle: Text(
                _permissionSnapshot == null
                    ? '확인 중'
                    : '카메라 ${_permissionText(_permissionSnapshot!.camera)} · '
                        '마이크 ${_permissionText(_permissionSnapshot!.microphone)} · '
                        '알림 ${_permissionText(_permissionSnapshot!.notification)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                _permissionSnapshot = await _permissions.requestEssential();
                if (mounted) setState(() {});
              },
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('알림 사용'),
              value: _notificationsEnabled,
              onChanged: (value) async {
                await _prefs.setNotificationsEnabled(value);
                if (!value) await NotificationService.instance.cancelAll();
                if (mounted) setState(() => _notificationsEnabled = value);
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('알림 테스트'),
              onTap: () async {
                await NotificationService.instance.showTest();
                _snack('테스트 알림을 전송했습니다.');
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.medication_liquid_outlined),
              title: const Text('복약 알림 시간 설정'),
              onTap: _scheduleMedicationReminder,
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.sync_outlined),
              title: const Text('백그라운드 알림 유지'),
              subtitle: const Text('앱을 닫아도 예약된 알림을 유지합니다.'),
              value: _backgroundEnabled,
              onChanged: (value) async {
                await _prefs.setBackgroundEnabled(value);
                if (mounted) setState(() => _backgroundEnabled = value);
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Google Calendar 열기'),
              onTap: _openCalendar,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_applications_outlined),
              title: const Text('Android 앱 설정 열기'),
              onTap: () async => _permissions.openSettings(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text('데이터 및 진단', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('오류 로그'),
              subtitle: Text('${_logs.length}건'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: _logs.isEmpty
                      ? const [Text('저장된 오류가 없습니다.')]
                      : _logs
                          .map(
                            (log) => ListTile(
                              title: Text(log.stage),
                              subtitle: Text(log.message),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
          ),
          Card(
            color: const Color(0xFFFFECEC),
            child: ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              title: const Text(
                '건강 데이터 초기화',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('확인 문구 입력 후에만 삭제됩니다.'),
              onTap: _confirmReset,
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('앱 정보'),
              subtitle: Text('AI 건강비서 1.3.1 · 개인 건강관리 보조 도구'),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _chatPage(),
      _healthPage(),
      _recordsPage(),
      _settingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 건강비서'),
        actions: [
          IconButton(
            tooltip: '시스템 진단',
            onPressed: () async {
              _permissionSnapshot = await _permissions.inspect();
              if (mounted) setState(() => _tab = 3);
            },
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI 건강비서',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: '건강상태',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '저장 기록',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
