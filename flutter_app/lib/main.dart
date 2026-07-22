import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthApp());
}

class HealthApp extends StatefulWidget {
  const HealthApp({super.key});

  @override
  State<HealthApp> createState() => _HealthAppState();
}

class _HealthAppState extends State<HealthApp> {
  String _language = 'system';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _language = prefs.getString('language') ?? 'system');
  }

  Locale? get _locale {
    switch (_language) {
      case 'ko':
        return const Locale('ko');
      case 'en':
        return const Locale('en');
      case 'ja':
        return const Locale('ja');
      case 'zh':
        return const Locale('zh');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 건강비서',
      locale: _locale,
      supportedLocales: const [
        Locale('ko'),
        Locale('en'),
        Locale('ja'),
        Locale('zh'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16864B)),
        scaffoldBackgroundColor: const Color(0xFFF7FAF7),
      ),
      home: MainScreen(
        onLanguageChanged: (value) => setState(() => _language = value),
      ),
    );
  }
}

class ChatMessage {
  ChatMessage({required this.role, required this.text, this.images = const []});
  final String role;
  final String text;
  final List<Uint8List> images;
}

class SavedItem {
  SavedItem({required this.category, required this.summary, required this.createdAt});
  final String category;
  final String summary;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'category': category,
        'summary': summary,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedItem.fromJson(Map<String, dynamic> json) => SavedItem(
        category: json['category']?.toString() ?? 'unknown',
        summary: json['summary']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class AppLog {
  AppLog({required this.time, required this.stage, required this.message});
  final DateTime time;
  final String stage;
  final String message;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'stage': stage,
        'message': message,
      };

  factory AppLog.fromJson(Map<String, dynamic> json) => AppLog(
        time: DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
        stage: json['stage']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
      );

  String format() => '${time.toLocal()}\n단계: $stage\n오류: $message';
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.onLanguageChanged});
  final ValueChanged<String> onLanguageChanged;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _secureStorage = FlutterSecureStorage();
  final _picker = ImagePicker();
  final _speech = stt.SpeechToText();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<XFile> _selectedImages = [];
  final List<SavedItem> _savedItems = [];
  final List<AppLog> _logs = [];

  int _tabIndex = 0;
  bool _busy = false;
  bool _listening = false;
  String _language = 'system';

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('language') ?? 'system';
    try {
      final saved = jsonDecode(prefs.getString('saved_items') ?? '[]') as List<dynamic>;
      _savedItems.addAll(saved.map((e) => SavedItem.fromJson(Map<String, dynamic>.from(e as Map))));
      final logs = jsonDecode(prefs.getString('app_logs') ?? '[]') as List<dynamic>;
      _logs.addAll(logs.map((e) => AppLog.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (error) {
      _logs.insert(0, AppLog(time: DateTime.now(), stage: '저장 데이터 불러오기', message: error.toString()));
    }
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_items', jsonEncode(_savedItems.map((e) => e.toJson()).toList()));
    await prefs.setString('app_logs', jsonEncode(_logs.take(100).map((e) => e.toJson()).toList()));
  }

  Future<void> _addLog(String stage, Object error) async {
    final safe = error.toString().replaceAll(RegExp(r'AQ\.[A-Za-z0-9_\-]+'), '[API_KEY_HIDDEN]');
    _logs.insert(0, AppLog(time: DateTime.now(), stage: stage, message: safe));
    if (_logs.length > 100) _logs.removeRange(100, _logs.length);
    await _persist();
    if (mounted) setState(() {});
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickMultipleImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 72, maxWidth: 1600);
      if (files.isEmpty) return;
      final remain = 5 - _selectedImages.length;
      if (remain <= 0) {
        _showSnack('사진은 최대 5장까지 선택할 수 있습니다.');
        return;
      }
      setState(() => _selectedImages.addAll(files.take(remain)));
      if (files.length > remain) _showSnack('최대 5장까지만 추가했습니다.');
    } catch (error) {
      await _addLog('사진 여러 장 선택', error);
      _showSnack('사진을 불러오지 못했습니다.');
    }
  }

  Future<void> _takePhoto() async {
    if (_selectedImages.length >= 5) {
      _showSnack('사진은 최대 5장까지 추가할 수 있습니다.');
      return;
    }
    try {
      final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 72, maxWidth: 1600);
      if (file != null && mounted) setState(() => _selectedImages.add(file));
    } catch (error) {
      await _addLog('카메라 촬영', error);
      _showSnack('카메라를 사용할 수 없습니다.');
    }
  }

  Future<void> _toggleSpeech() async {
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      final available = await _speech.initialize();
      if (!available) throw Exception('음성 인식을 시작할 수 없습니다.');
      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        localeId: _language == 'system'
            ? null
            : {'ko': 'ko_KR', 'en': 'en_US', 'ja': 'ja_JP', 'zh': 'zh_CN'}[_language],
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _inputController.text = result.recognizedWords;
            _inputController.selection = TextSelection.collapsed(offset: _inputController.text.length);
            if (result.finalResult) _listening = false;
          });
        },
      );
    } catch (error) {
      await _addLog('음성 입력', error);
      if (mounted) setState(() => _listening = false);
      _showSnack('음성 입력을 사용할 수 없습니다.');
    }
  }

  String _responseLanguage() {
    switch (_language) {
      case 'en':
        return 'English';
      case 'ja':
        return 'Japanese';
      case 'zh':
        return 'Simplified Chinese';
      default:
        return 'Korean';
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _inputController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty) return;

    final apiKey = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (apiKey.isEmpty) {
      _showSnack('설정에서 Gemini API 키를 먼저 입력하세요.');
      setState(() => _tabIndex = 2);
      return;
    }

    final imageBytes = <Uint8List>[];
    try {
      for (final image in _selectedImages) {
        imageBytes.add(await image.readAsBytes());
      }
    } catch (error) {
      await _addLog('사진 읽기', error);
      _showSnack('선택한 사진을 읽지 못했습니다.');
      return;
    }

    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        text: text.isEmpty ? '사진 ${imageBytes.length}장 분석' : text,
        images: imageBytes,
      ));
      _inputController.clear();
      _selectedImages.clear();
      _busy = true;
    });
    _scrollToBottom();

    try {
      final parts = <Map<String, dynamic>>[
        {
          'text': '''당신은 개인 건강기록 정리 도우미입니다.
사용자의 자연어와 첨부 사진을 함께 분석하세요.
응답 언어: ${_responseLanguage()}.
분류: vitals, body, meal, medication, symptom, activity, medical_history, document, hospital_schedule, prevention, unknown.
확정 정보와 추정 정보를 구분하세요.
의료 진단이나 약 변경 지시는 하지 마세요.
마지막에 반드시 다음 JSON 블록을 포함하세요.
```json
{"items":[{"category":"분류","summary":"저장할 핵심 내용"}]}
```
사용자 입력: ${text.isEmpty ? '첨부된 사진들을 하나의 자료 묶음으로 종합 분석해 주세요.' : text}''',
        },
      ];
      for (final bytes in imageBytes) {
        parts.add({'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(bytes)}});
      }

      final response = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
            body: jsonEncode({
              'contents': [
                {'parts': parts}
              ],
              'generationConfig': {'temperature': 0.2},
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = response.body.length > 400 ? response.body.substring(0, 400) : response.body;
        throw Exception('Gemini HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      final answer = candidates != null && candidates.isNotEmpty
          ? ((candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?)?['parts']
                  ?.letText() ??
              '응답을 읽지 못했습니다.'
          : '응답을 읽지 못했습니다.';

      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(role: 'assistant', text: answer)));
      await _offerSave(answer);
    } catch (error) {
      await _addLog('Gemini 분석', error);
      if (mounted) {
        setState(() => _messages.add(ChatMessage(
              role: 'assistant',
              text: '분석에 실패했습니다. 설정의 오류 로그에서 자세한 내용을 확인하고 복사할 수 있습니다.',
            )));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  Future<void> _offerSave(String answer) async {
    final match = RegExp(r'```json\s*(\{[\s\S]*?\})\s*```').firstMatch(answer);
    if (match == null || !mounted) return;
    try {
      final decoded = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final items = decoded['items'] as List<dynamic>? ?? [];
      if (items.isEmpty) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('분석 결과 저장'),
          content: Text('${items.length}개 항목을 건강 데이터로 저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('저장')),
          ],
        ),
      );
      if (confirmed != true) return;
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        _savedItems.insert(
          0,
          SavedItem(
            category: item['category']?.toString() ?? 'unknown',
            summary: item['summary']?.toString() ?? '',
            createdAt: DateTime.now(),
          ),
        );
      }
      await _persist();
      if (mounted) setState(() {});
    } catch (error) {
      await _addLog('분석 결과 저장', error);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[_chatPage(), _recordsPage(), _settingsPage()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tabIndex, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI 건강비서'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '저장 기록'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }

  Widget _chatPage() {
    return Column(
      children: [
        const ListTile(
          title: Text('AI 건강비서', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          subtitle: Text('대화·사진·촬영·음성으로 입력하세요'),
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '예: “오늘 공복 혈당 126이야”\n처방전이나 약봉투 사진은 최대 5장까지 한 번에 분석할 수 있습니다.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message.role == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.images.isNotEmpty)
                              SizedBox(
                                height: 90,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: message.images.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                                  itemBuilder: (_, imageIndex) => ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(message.images[imageIndex], width: 90, height: 90, fit: BoxFit.cover),
                                  ),
                                ),
                              ),
                            if (message.images.isNotEmpty) const SizedBox(height: 8),
                            SelectableText(message.text),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_selectedImages.isNotEmpty) _selectedImagesBar(),
        _inputBar(),
      ],
    );
  }

  Widget _selectedImagesBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 92,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _selectedImages.length,
            itemBuilder: (context, index) {
              return FutureBuilder<Uint8List>(
                future: _selectedImages[index].readAsBytes(),
                builder: (context, snapshot) {
                  return Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black12),
                        child: snapshot.hasData
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                              )
                            : const Center(child: CircularProgressIndicator()),
                      ),
                      Positioned(
                        right: 4,
                        top: 0,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _selectedImages.removeAt(index)),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('선택된 사진 ${_selectedImages.length}/5장'),
        ),
      ],
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (value) => value == 'gallery' ? _pickMultipleImages() : _takePhoto(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'gallery', child: Text('사진 여러 장 선택')),
                PopupMenuItem(value: 'camera', child: Text('카메라 촬영')),
              ],
            ),
            IconButton(icon: Icon(_listening ? Icons.mic : Icons.mic_none), onPressed: _toggleSpeech),
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '건강 내용을 편하게 입력하세요',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordsPage() {
    return Column(
      children: [
        const ListTile(
          title: Text('저장 기록', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          subtitle: Text('AI 분석 후 확인하여 저장한 데이터'),
        ),
        Expanded(
          child: _savedItems.isEmpty
              ? const Center(child: Text('저장된 기록이 없습니다.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _savedItems.length,
                  itemBuilder: (context, index) {
                    final item = _savedItems[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.health_and_safety_outlined),
                        title: Text(item.category),
                        subtitle: Text('${item.summary}\n${item.createdAt.toLocal()}'),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            setState(() => _savedItems.removeAt(index));
                            await _persist();
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('설정', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.key), title: const Text('Gemini API 키'), subtitle: const Text('기기에 안전하게 저장하고 연결을 확인합니다.'), onTap: _showApiDialog)),
        Card(child: ListTile(leading: const Icon(Icons.language), title: const Text('언어'), subtitle: Text(_languageLabel(_language)), onTap: _showLanguageDialog)),
        Card(child: ListTile(leading: const Icon(Icons.bug_report_outlined), title: const Text('오류 로그'), subtitle: Text('${_logs.length}개 저장됨 · 복사 및 AI 분석 가능'), onTap: _showLogsDialog)),
        const Card(child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('사진 분석'), subtitle: Text('한 번에 최대 5장'))),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('모든 건강 기록 삭제'),
            onTap: () async {
              setState(() => _savedItems.clear());
              await _persist();
            },
          ),
        ),
        const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('앱 정보'), subtitle: Text('AI 건강비서 2.2.0'))),
      ],
    );
  }

  String _languageLabel(String value) => {
        'system': '시스템 설정 따름',
        'ko': '한국어',
        'en': 'English',
        'ja': '日本語',
        'zh': '简体中文',
      }[value] ?? value;

  Future<void> _showLanguageDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('언어 선택'),
        children: ['system', 'ko', 'en', 'ja', 'zh']
            .map((value) => RadioListTile<String>(
                  value: value,
                  groupValue: _language,
                  title: Text(_languageLabel(value)),
                  onChanged: (newValue) => Navigator.pop(dialogContext, newValue),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', selected);
    if (!mounted) return;
    setState(() => _language = selected);
    widget.onLanguageChanged(selected);
  }

  Future<void> _showApiDialog() async {
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
              try {
                final response = await http
                    .post(
                      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
                      headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
                      body: jsonEncode({
                        'contents': [
                          {
                            'parts': [
                              {'text': 'Reply only OK'}
                            ]
                          }
                        ]
                      }),
                    )
                    .timeout(const Duration(seconds: 20));
                if (response.statusCode < 200 || response.statusCode >= 300) {
                  throw Exception('HTTP ${response.statusCode}: ${response.body}');
                }
                _showSnack('API 연결 성공');
              } catch (error) {
                await _addLog('API 연결 테스트', error);
                _showSnack('연결 실패. 오류 로그를 확인하세요.');
              }
            },
            child: const Text('연결 테스트'),
          ),
          FilledButton(
            onPressed: () async {
              await _secureStorage.write(key: 'gemini_api_key', value: controller.text.trim());
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showLogsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('오류 로그'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: _logs.isEmpty
              ? const Center(child: Text('저장된 오류가 없습니다.'))
              : ListView.separated(
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, index) => SelectableText(_logs[index].format()),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final text = _logs.map((e) => e.format()).join('\n\n---\n\n');
              await Clipboard.setData(ClipboardData(text: text));
              _showSnack('오류 로그를 복사했습니다.');
            },
            child: const Text('전체 복사'),
          ),
          TextButton(
            onPressed: () {
              final text = _logs.take(10).map((e) => e.format()).join('\n\n');
              Navigator.pop(dialogContext);
              setState(() {
                _tabIndex = 0;
                _inputController.text = '아래 앱 오류 로그를 분석해서 원인과 해결 순서를 알려줘.\n\n$text';
              });
            },
            child: const Text('AI로 분석'),
          ),
          TextButton(
            onPressed: () async {
              setState(() => _logs.clear());
              await _persist();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('삭제'),
          ),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('닫기')),
        ],
      ),
    );
  }
}

extension _GeminiPartsText on Object? {
  String? letText() {
    final value = this;
    if (value is! List || value.isEmpty) return null;
    final first = value.first;
    if (first is! Map) return null;
    return first['text']?.toString();
  }
}
