import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import 'gemini_service.dart';
import 'models.dart';
import 'record_detail_page.dart';
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
  final _speech = stt.SpeechToText();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<ChatEntry> _messages = [];
  final List<XFile> _images = [];
  final List<HealthRecord> _records = [];
  final List<ErrorLogEntry> _logs = [];

  HealthProfile _profile = const HealthProfile();
  int _tab = 0;
  bool _busy = false;
  bool _listening = false;
  String _language = 'system';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _speech.stop();
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

  Future<void> _log(String stage, Object error) async {
    final safe = error.toString().replaceAll(
          RegExp(r'(AIza|AQ\.)[A-Za-z0-9_\-\.]+'),
          '[API_KEY_HIDDEN]',
        );
    _logs.insert(0, ErrorLogEntry(time: DateTime.now(), stage: stage, message: safe));
    if (_logs.length > 100) _logs.removeRange(100, _logs.length);
    await _save();
    if (mounted) setState(() {});
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

  Future<void> _pickImages() async {
    try {
      final selected = await _picker.pickMultiImage(imageQuality: 78, maxWidth: 1600);
      if (selected.isEmpty) return;
      final remain = 5 - _images.length;
      if (remain <= 0) {
        _snack('사진은 최대 5장까지 선택할 수 있습니다.');
        return;
      }
      setState(() => _images.addAll(selected.take(remain)));
      if (selected.length > remain) _snack('최대 5장까지만 추가했습니다.');
    } catch (error) {
      await _log('gallery', error);
      _snack('사진을 불러오지 못했습니다.');
    }
  }

  Future<void> _takePhoto({int? replaceIndex}) async {
    try {
      if (replaceIndex == null && _images.length >= 5) {
        _snack('사진은 최대 5장까지 추가할 수 있습니다.');
        return;
      }
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 78,
        maxWidth: 1600,
      );
      if (photo == null || !mounted) return;
      setState(() {
        if (replaceIndex == null) {
          _images.add(photo);
        } else {
          _images[replaceIndex] = photo;
        }
      });
    } catch (error) {
      await _log('camera', error);
      _snack('카메라를 사용할 수 없습니다.');
    }
  }

  Future<void> _previewImage(int index) async {
    final bytes = await _images[index].readAsBytes();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSpeech() async {
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      final available = await _speech.initialize();
      if (!available) throw Exception('음성 인식을 사용할 수 없습니다.');
      if (!mounted) return;
      setState(() => _listening = true);
      await _speech.listen(
        localeId: switch (_language) {
          'ko' => 'ko_KR',
          'en' => 'en_US',
          'ja' => 'ja_JP',
          'zh' => 'zh_CN',
          _ => null,
        },
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _input.text = result.recognizedWords;
            _input.selection = TextSelection.collapsed(offset: _input.text.length);
            if (result.finalResult) _listening = false;
          });
        },
      );
    } catch (error) {
      await _log('speech', error);
      if (mounted) setState(() => _listening = false);
      _snack('음성 입력을 시작하지 못했습니다.');
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty && _images.isEmpty) return;

    final key = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (key.isEmpty) {
      setState(() => _tab = 3);
      _snack('설정에서 Gemini API 키를 먼저 입력하세요.');
      return;
    }

    final imageBytes = <List<int>>[];
    try {
      for (final image in _images) {
        imageBytes.add(await image.readAsBytes());
      }
    } catch (error) {
      await _log('image_read', error);
      _snack('사진을 읽지 못했습니다.');
      return;
    }

    final userText = text.isEmpty ? '첨부한 사진 ${imageBytes.length}장을 종합 분석해줘.' : text;
    setState(() {
      _messages.add(ChatEntry(role: 'user', text: userText, images: imageBytes));
      _input.clear();
      _images.clear();
      _busy = true;
    });
    _scrollBottom();

    try {
      final result = await _gemini.analyze(
        apiKey: key,
        userText: userText,
        images: imageBytes,
        profile: _profile,
        responseLanguage: _responseLanguage,
      );

      final visible = result.followUpQuestion.isEmpty
          ? result.answer
          : '${result.answer}\n\n확인을 위해 알려주세요:\n${result.followUpQuestion}';
      if (!mounted) return;
      setState(() => _messages.add(ChatEntry(role: 'assistant', text: visible)));
      _scrollBottom();

      if (result.records.isNotEmpty ||
          result.profileUpdate.isNotEmpty ||
          result.calendarSuggestions.isNotEmpty) {
        await _confirmResult(result, sourceText: userText);
      }
    } on TimeoutException catch (error) {
      await _log('gemini_timeout', error);
      _friendlyError('분석 시간이 초과되었습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.');
    } on FormatException catch (error) {
      await _log('gemini_format', error);
      _friendlyError('AI 답변을 정리하는 중 오류가 발생했습니다. 다시 분석해 주세요.');
    } catch (error) {
      await _log('gemini', error);
      _friendlyError('분석하지 못했습니다. 설정의 오류 로그에서 원인을 확인할 수 있습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _friendlyError(String text) {
    if (!mounted) return;
    setState(() => _messages.add(ChatEntry(role: 'assistant', text: text)));
    _scrollBottom();
  }

  Future<void> _confirmResult(GeminiResult result, {required String sourceText}) async {
    final selected = List<bool>.filled(result.records.length, true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('분석 결과 확인', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('분류된 기록과 건강 프로필 업데이트를 확인하세요.'),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        ...List.generate(result.records.length, (index) {
                          final item = result.records[index];
                          return CheckboxListTile(
                            value: selected[index],
                            onChanged: (value) => setSheetState(() => selected[index] = value ?? false),
                            title: Text(item['title']?.toString() ?? '건강 기록'),
                            subtitle: Text(item['summary']?.toString() ?? ''),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }),
                        if (result.profileUpdate.isNotEmpty)
                          Card(
                            color: const Color(0xFFE7F4EA),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('건강 프로필 업데이트\n${_profileUpdateText(result.profileUpdate)}'),
                            ),
                          ),
                        if (result.calendarSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Google Calendar 일정 제안', style: TextStyle(fontWeight: FontWeight.w900)),
                          ...result.calendarSuggestions.map(
                            (event) => ListTile(
                              leading: const Icon(Icons.calendar_month),
                              title: Text(event.title),
                              subtitle: Text('${_formatDate(event.start)}\n${event.description}'),
                              isThreeLine: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final added = <HealthRecord>[];
                            for (var i = 0; i < result.records.length; i++) {
                              if (!selected[i]) continue;
                              final item = result.records[i];
                              added.add(
                                HealthRecord(
                                  id: '${DateTime.now().microsecondsSinceEpoch}$i',
                                  category: item['category']?.toString() ?? 'other',
                                  title: item['title']?.toString() ?? '건강 기록',
                                  summary: item['summary']?.toString() ?? '',
                                  details: Map<String, dynamic>.from((item['details'] as Map?) ?? const {}),
                                  createdAt: DateTime.now(),
                                  inputMethod: _messages.last.images.isEmpty ? 'chat' : 'image',
                                  confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
                                  sourceText: sourceText,
                                ),
                              );
                            }
                            setState(() {
                              _records.insertAll(0, added);
                              _profile = _profile.merged(result.profileUpdate);
                            });
                            await _save();
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                            if (result.calendarSuggestions.isNotEmpty) {
                              await _showCalendarSuggestions(result.calendarSuggestions);
                            } else {
                              _snack('${added.length}건을 저장했습니다.');
                            }
                          },
                          child: const Text('저장하고 계속'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _profileUpdateText(Map<String, dynamic> update) {
    final lines = <String>[];
    void add(String label, String key) {
      final value = update[key];
      if (value is List && value.isNotEmpty) lines.add('$label: ${value.join(', ')}');
    }

    add('확정 질환', 'confirmedConditions');
    add('추정 질환', 'inferredConditions');
    add('복용약', 'medications');
    add('알레르기', 'allergies');
    add('메모', 'notes');
    return lines.isEmpty ? '변경 없음' : lines.join('\n');
  }

  Future<void> _showCalendarSuggestions(List<CalendarSuggestion> events) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Google Calendar 등록'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: events
                .map(
                  (event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available),
                    title: Text(event.title),
                    subtitle: Text(_formatDate(event.start)),
                    trailing: FilledButton.tonal(
                      onPressed: () => _openCalendar(event),
                      child: const Text('등록'),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('닫기'))],
      ),
    );
  }

  Future<void> _openCalendar(CalendarSuggestion event) async {
    String utc(DateTime value) {
      final v = value.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${v.year}${two(v.month)}${two(v.day)}T${two(v.hour)}${two(v.minute)}${two(v.second)}Z';
    }

    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': event.title,
      'dates': '${utc(event.start)}/${utc(event.end)}',
      'details': event.description,
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _snack('Google Calendar를 열지 못했습니다.');
      return;
    }
    setState(() {
      _messages.add(
        ChatEntry(
          role: 'assistant',
          text: 'Google Calendar 등록 화면을 열었습니다.\n"${event.title}" 일정을 확인하고 저장해 주세요.',
        ),
      );
    });
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatDate(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _categoryLabel(String category) => switch (category) {
        'medication' => '복약',
        'condition' => '질환',
        'hospital' => '병원 기록',
        'schedule' => '일정',
        'lab' => '검사 결과',
        'vital' => '건강 수치',
        'diet' => '식단',
        'symptom' => '증상',
        'document' => '문서',
        'activity' => '활동',
        _ => '기타',
      };

  IconData _categoryIcon(String category) => switch (category) {
        'medication' => Icons.medication,
        'condition' => Icons.health_and_safety,
        'hospital' => Icons.local_hospital,
        'schedule' => Icons.calendar_month,
        'lab' => Icons.science,
        'vital' => Icons.monitor_heart,
        'diet' => Icons.restaurant,
        'symptom' => Icons.sick,
        'document' => Icons.description,
        'activity' => Icons.directions_run,
        _ => Icons.folder,
      };

  Widget _metric(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF176F46)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    final latest = _records.take(3).toList();
    return Column(
      children: [
        Card(
          color: const Color(0xFF176F46),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.add_box_rounded, size: 40, color: Color(0xFF176F46)),
                      Positioned(right: 8, top: 8, child: Icon(Icons.eco, size: 22, color: Color(0xFF36A65E))),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI 건강비서', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                        _profile.isSparse
                            ? '맞춤 분석을 위해 건강상태를 알려주세요.'
                            : '저장된 건강정보를 바탕으로 답변합니다.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _metric('저장 기록', '${_records.length}건', Icons.folder_open),
            const SizedBox(width: 8),
            _metric('복용약', '${_profile.medications.length}개', Icons.medication),
            const SizedBox(width: 8),
            _metric('건강상태', '${_profile.confirmedConditions.length + _profile.inferredConditions.length}개', Icons.favorite),
          ],
        ),
        if (_profile.isSparse) ...[
          const SizedBox(height: 10),
          Card(
            color: const Color(0xFFFFF2CD),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('건강 프로필이 비어 있습니다', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('질환, 복용약, 알레르기 등을 알려주면 식단과 처방전 분석이 더 정확해집니다.'),
              trailing: TextButton(
                onPressed: () {
                  _input.text = '맞춤 건강관리를 위해 내 건강상태를 하나씩 질문해줘.';
                  _input.selection = TextSelection.collapsed(offset: _input.text.length);
                },
                child: const Text('입력'),
              ),
            ),
          ),
        ],
        if (latest.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('최근 저장 기록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ...latest.map(
                    (record) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_categoryIcon(record.category)),
                      title: Text(record.title),
                      subtitle: Text(record.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _openRecord(record),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chatPage() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                _dashboard(),
                const SizedBox(height: 14),
                if (_messages.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.auto_awesome, size: 38, color: Color(0xFF176F46)),
                          const SizedBox(height: 8),
                          const Text('무엇을 도와드릴까요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          const Text(
                            '처방전·검사결과·식단 사진을 보내거나\n현재 증상과 건강상태를 대화로 알려주세요.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _quick('처방전 분석'),
                              _quick('복용약으로 질환 확인'),
                              _quick('내 건강상태에 맞는 식단'),
                              _quick('최근 저장 기록 보여줘'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ..._messages.map(_bubble),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('건강정보를 분석하고 있습니다...'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_images.isNotEmpty) _imageStrip(),
          _composer(),
        ],
      ),
    );
  }

  Widget _quick(String text) => ActionChip(
        label: Text(text),
        onPressed: () {
          _input.text = text;
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        },
      );

  Widget _bubble(ChatEntry entry) {
    final user = entry.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: user ? const Color(0xFFB9F1C6) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: user ? null : Border.all(color: const Color(0xFFE0E5E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.images.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: entry.images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(Uint8List.fromList(entry.images[index]), width: 90, fit: BoxFit.cover),
                  ),
                ),
              ),
            if (entry.images.isNotEmpty) const SizedBox(height: 10),
            Text(entry.text, style: const TextStyle(fontSize: 16, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _imageStrip() {
    return SizedBox(
      height: 104,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _images.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final image = _images.removeAt(oldIndex);
            _images.insert(newIndex, image);
          });
        },
        itemBuilder: (context, index) => FutureBuilder<Uint8List>(
          key: ValueKey(_images[index].path),
          future: _images[index].readAsBytes(),
          builder: (context, snapshot) => Container(
            width: 92,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.grey.shade200,
              image: snapshot.hasData ? DecorationImage(image: MemoryImage(snapshot.data!), fit: BoxFit.cover) : null,
            ),
            child: Stack(
              children: [
                Positioned.fill(child: InkWell(onTap: () => _previewImage(index))),
                Positioned(
                  top: 2,
                  right: 2,
                  child: CircleAvatar(
                    radius: 13,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 15,
                      onPressed: () => setState(() => _images.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: CircleAvatar(
                    radius: 13,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 15,
                      onPressed: () => _takePhoto(replaceIndex: index),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline, size: 30),
              onSelected: (value) {
                if (value == 'gallery') _pickImages();
                if (value == 'camera') _takePhoto();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library), title: Text('사진 선택'))),
                PopupMenuItem(value: 'camera', child: ListTile(leading: Icon(Icons.camera_alt), title: Text('연속 촬영'))),
              ],
            ),
            IconButton(
              onPressed: _toggleSpeech,
              icon: Icon(_listening ? Icons.stop_circle : Icons.mic, size: 30),
              color: _listening ? Colors.red : null,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: '건강 내용을 편하게 입력하세요',
                  filled: true,
                  fillColor: const Color(0xFFF2F5F2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.arrow_upward)),
          ],
        ),
      ),
    );
  }

  Widget _profileSection(String title, List<String> values, {bool inferred = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (values.isEmpty)
              const Text('등록된 정보가 없습니다.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: values
                    .map(
                      (value) => Chip(
                        avatar: inferred ? const Icon(Icons.help_outline, size: 18) : null,
                        label: Text(value),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _profilePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('내 건강상태', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const Text('AI가 처방전·약·검사결과와 대화를 연결해 관리합니다.'),
        const SizedBox(height: 16),
        _profileSection('확정 질환', _profile.confirmedConditions),
        const SizedBox(height: 10),
        _profileSection('복용약으로 추정한 질환', _profile.inferredConditions, inferred: true),
        const SizedBox(height: 10),
        _profileSection('복용 중인 약', _profile.medications),
        const SizedBox(height: 10),
        _profileSection('알레르기', _profile.allergies),
        const SizedBox(height: 10),
        _profileSection('건강 메모', _profile.notes),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () {
            setState(() => _tab = 0);
            _input.text = '내 건강상태를 점검하고 부족한 정보를 하나씩 질문해줘.';
          },
          icon: const Icon(Icons.chat),
          label: const Text('AI와 건강상태 입력하기'),
        ),
      ],
    );
  }

  Widget _recordsPage() {
    final categories = <String>{'all', ..._records.map((e) => e.category)}.toList();
    final visible = _filter == 'all' ? _records : _records.where((e) => e.category == _filter).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('저장 기록', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
              const Text('기록을 눌러 AI 요약, 세부 데이터와 원본 입력을 확인하세요.'),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final category = categories[index];
                    return ChoiceChip(
                      selected: _filter == category,
                      label: Text(category == 'all' ? '전체' : _categoryLabel(category)),
                      onSelected: (_) => setState(() => _filter = category),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('저장된 기록이 없습니다.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final record = visible[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(child: Icon(_categoryIcon(record.category))),
                        title: Text(record.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${record.summary}\n${_formatDate(record.createdAt)}'),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openRecord(record),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openRecord(HealthRecord record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordDetailPage(
          record: record,
          categoryLabel: _categoryLabel(record.category),
          categoryIcon: _categoryIcon(record.category),
          onDelete: () async {
            setState(() => _records.removeWhere((e) => e.id == record.id));
            await _save();
          },
        ),
      ),
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('설정', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Gemini API 키'),
                subtitle: const Text('키 저장·삭제·연결 테스트'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showApiSettings,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('언어'),
                subtitle: Text(_language == 'system' ? '시스템 설정 따름' : _language),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showLanguageSettings,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('오류 로그'),
                subtitle: Text('${_logs.length}건'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showLogs,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xFFE7F4EA),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              '개인정보 안내\nAPI 키는 보안 저장소에 보관하며 오류 로그에는 남기지 않습니다. '
              '복용약으로 추정한 질환은 사용자 확인 전까지 확정 진단으로 취급하지 않습니다.',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showApiSettings() async {
    final current = await _secureStorage.read(key: 'gemini_api_key') ?? '';
    final controller = TextEditingController(text: current);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gemini API 키'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'API 키', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _secureStorage.delete(key: 'gemini_api_key');
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('삭제'),
          ),
          TextButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) return;
              await _secureStorage.write(key: 'gemini_api_key', value: key);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _testApi();
            },
            child: const Text('저장 후 테스트'),
          ),
        ],
      ),
    );
  }

  Future<void> _testApi() async {
    try {
      final key = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
      if (key.isEmpty) throw Exception('API 키가 없습니다.');
      await _gemini.testConnection(key);
      _snack('Gemini 연결이 정상입니다.');
    } catch (error) {
      await _log('api_test', error);
      _snack('연결하지 못했습니다. 오류 로그를 확인해 주세요.');
    }
  }

  Future<void> _showLanguageSettings() async {
    final options = {
      'system': '시스템 설정 따름',
      'ko': '한국어',
      'en': 'English',
      'ja': '日本語',
      'zh': '简体中文',
    };
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('언어 선택'),
        children: options.entries
            .map(
              (entry) => ListTile(
                leading: _language == entry.key ? const Icon(Icons.check) : const SizedBox(width: 24),
                title: Text(entry.value),
                onTap: () => Navigator.pop(dialogContext, entry.key),
              ),
            )
            .toList(),
      ),
    );
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
    setState(() => _language = value);
    widget.onLanguageChanged(value);
  }

  Future<void> _showLogs() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .78,
          child: Column(
            children: [
              const Text('오류 로그', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              Expanded(
                child: _logs.isEmpty
                    ? const Center(child: Text('저장된 오류가 없습니다.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, index) {
                          final log = _logs[index];
                          return ListTile(
                            title: Text(log.stage),
                            subtitle: Text('${log.time.toLocal()}\n${log.message}'),
                            isThreeLine: true,
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final text = _logs
                              .map((e) => '${e.time.toLocal()}\n단계: ${e.stage}\n오류: ${e.message}')
                              .join('\n\n');
                          Clipboard.setData(ClipboardData(text: text));
                          _snack('오류 로그를 복사했습니다.');
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('전체 복사'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          setState(() => _logs.clear());
                          await _save();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('전체 삭제'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_chatPage(), _profilePage(), _recordsPage(), _settingsPage()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI 건강비서'),
          NavigationDestination(icon: Icon(Icons.favorite_outline), label: '건강상태'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '저장 기록'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '설정'),
        ],
      ),
    );
  }
}
