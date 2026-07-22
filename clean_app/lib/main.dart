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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthAssistantApp());
}

class HealthAssistantApp extends StatefulWidget {
  const HealthAssistantApp({super.key});

  @override
  State<HealthAssistantApp> createState() => _HealthAssistantAppState();
}

class _HealthAssistantAppState extends State<HealthAssistantApp> {
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
    return switch (_language) {
      'ko' => const Locale('ko'),
      'en' => const Locale('en'),
      'ja' => const Locale('ja'),
      'zh' => const Locale('zh'),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Health Assistant',
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF25734A)),
        scaffoldBackgroundColor: const Color(0xFFF7FAF7),
      ),
      home: HomeScreen(
        initialLanguage: _language,
        onLanguageChanged: (value) => setState(() => _language = value),
      ),
    );
  }
}

class AppText {
  static const Map<String, Map<String, String>> _values = {
    'ko': {
      'title': 'AI 건강비서',
      'subtitle': '대화·사진·촬영·음성으로 입력하세요',
      'hint': '건강 내용을 편하게 입력하세요',
      'empty': '건강 기록이나 사진을 보내면 AI가 분석하고\n저장할 항목을 확인해 드립니다.',
      'records': '건강기록',
      'settings': '설정',
      'chat': 'AI 대화',
      'api': 'Gemini API 키',
      'language': '언어',
      'logs': '오류 로그',
      'save': '저장',
      'cancel': '취소',
      'delete': '삭제',
      'copy': '복사',
      'test': '연결 테스트',
      'system': '시스템 설정 따름',
    },
    'en': {
      'title': 'AI Health Assistant',
      'subtitle': 'Use chat, photos, camera, or voice',
      'hint': 'Enter your health information',
      'empty': 'Send a health note or photos. AI will analyze them\nand ask before saving structured records.',
      'records': 'Records',
      'settings': 'Settings',
      'chat': 'AI Chat',
      'api': 'Gemini API key',
      'language': 'Language',
      'logs': 'Error logs',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'copy': 'Copy',
      'test': 'Test connection',
      'system': 'Follow system language',
    },
    'ja': {
      'title': 'AI健康アシスタント',
      'subtitle': '会話・写真・撮影・音声で入力',
      'hint': '健康情報を入力してください',
      'empty': '健康記録や写真を送るとAIが分析し、\n保存前に確認します。',
      'records': '健康記録',
      'settings': '設定',
      'chat': 'AI会話',
      'api': 'Gemini APIキー',
      'language': '言語',
      'logs': 'エラーログ',
      'save': '保存',
      'cancel': 'キャンセル',
      'delete': '削除',
      'copy': 'コピー',
      'test': '接続テスト',
      'system': 'システム言語を使用',
    },
    'zh': {
      'title': 'AI健康助手',
      'subtitle': '通过对话、照片、拍摄或语音输入',
      'hint': '请输入健康信息',
      'empty': '发送健康记录或照片后，AI会分析，\n并在保存前让您确认。',
      'records': '健康记录',
      'settings': '设置',
      'chat': 'AI对话',
      'api': 'Gemini API密钥',
      'language': '语言',
      'logs': '错误日志',
      'save': '保存',
      'cancel': '取消',
      'delete': '删除',
      'copy': '复制',
      'test': '连接测试',
      'system': '跟随系统语言',
    },
  };

  static String get(String language, String key) {
    final resolved = language == 'system' ? 'ko' : language;
    return _values[resolved]?[key] ?? _values['ko']![key]!;
  }
}

class HealthRecord {
  HealthRecord({
    required this.id,
    required this.category,
    required this.type,
    required this.summary,
    required this.occurredAt,
    required this.inputMethod,
    required this.confidence,
  });

  final String id;
  final String category;
  final String type;
  final String summary;
  final DateTime occurredAt;
  final String inputMethod;
  final double confidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'type': type,
        'summary': summary,
        'occurredAt': occurredAt.toIso8601String(),
        'inputMethod': inputMethod,
        'confidence': confidence,
      };

  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        category: json['category']?.toString() ?? 'unknown',
        type: json['type']?.toString() ?? 'unknown',
        summary: json['summary']?.toString() ?? '',
        occurredAt: DateTime.tryParse(json['occurredAt']?.toString() ?? '') ?? DateTime.now(),
        inputMethod: json['inputMethod']?.toString() ?? 'chat',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );
}

class ErrorLogEntry {
  ErrorLogEntry({required this.time, required this.stage, required this.message});

  final DateTime time;
  final String stage;
  final String message;

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'stage': stage,
        'message': message,
      };

  factory ErrorLogEntry.fromJson(Map<String, dynamic> json) => ErrorLogEntry(
        time: DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
        stage: json['stage']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
      );
}

class ChatEntry {
  ChatEntry({required this.role, required this.text, this.images = const []});

  final String role;
  final String text;
  final List<Uint8List> images;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialLanguage,
    required this.onLanguageChanged,
  });

  final String initialLanguage;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _model = 'gemini-2.5-flash';

  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _input = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  final List<ChatEntry> _messages = [];
  final List<XFile> _images = [];
  final List<HealthRecord> _records = [];
  final List<ErrorLogEntry> _logs = [];

  int _tab = 0;
  bool _busy = false;
  bool _listening = false;
  String _language = 'system';

  String t(String key) => AppText.get(_language, key);

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _loadLocalData();
  }

  @override
  void dispose() {
    _input.dispose();
    _chatScroll.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final recordJson = jsonDecode(prefs.getString('health_records_v1') ?? '[]') as List<dynamic>;
      final logJson = jsonDecode(prefs.getString('error_logs_v1') ?? '[]') as List<dynamic>;
      _records
        ..clear()
        ..addAll(recordJson.map((item) => HealthRecord.fromJson(Map<String, dynamic>.from(item as Map))));
      _logs
        ..clear()
        ..addAll(logJson.map((item) => ErrorLogEntry.fromJson(Map<String, dynamic>.from(item as Map))));
    } catch (error) {
      _logs.insert(0, ErrorLogEntry(time: DateTime.now(), stage: 'local_data_load', message: error.toString()));
    }
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('health_records_v1', jsonEncode(_records.map((e) => e.toJson()).toList()));
    await prefs.setString('error_logs_v1', jsonEncode(_logs.take(100).map((e) => e.toJson()).toList()));
  }

  Future<void> _log(String stage, Object error) async {
    final safe = error
        .toString()
        .replaceAll(RegExp(r'(AIza|AQ\.)[A-Za-z0-9_\-\.]+'), '[API_KEY_HIDDEN]');
    _logs.insert(0, ErrorLogEntry(time: DateTime.now(), stage: stage, message: safe));
    if (_logs.length > 100) _logs.removeRange(100, _logs.length);
    await _persist();
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImages() async {
    try {
      final selected = await _picker.pickMultiImage(imageQuality: 78, maxWidth: 1600);
      if (selected.isEmpty) return;
      final remaining = 5 - _images.length;
      if (remaining <= 0) {
        _snack('사진은 최대 5장까지 선택할 수 있습니다.');
        return;
      }
      setState(() => _images.addAll(selected.take(remaining)));
      if (selected.length > remaining) _snack('최대 5장까지만 추가했습니다.');
    } catch (error) {
      await _log('gallery', error);
      _snack('사진을 불러오지 못했습니다. 권한과 저장공간을 확인해 주세요.');
    }
  }

  Future<void> _takePhoto({int? replaceIndex}) async {
    try {
      if (replaceIndex == null && _images.length >= 5) {
        _snack('사진은 최대 5장까지 추가할 수 있습니다.');
        return;
      }
      final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 78, maxWidth: 1600);
      if (photo == null || !mounted) return;
      setState(() {
        if (replaceIndex != null) {
          _images[replaceIndex] = photo;
        } else {
          _images.add(photo);
        }
      });
    } catch (error) {
      await _log('camera', error);
      _snack('카메라를 사용할 수 없습니다. 카메라 권한을 확인해 주세요.');
    }
  }

  Future<void> _previewImage(int index) async {
    try {
      final bytes = await _images[index].readAsBytes();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Stack(
            children: [
              InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      await _log('image_preview', error);
      _snack('사진을 확대해서 열지 못했습니다.');
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
      if (!available) throw StateError('Speech recognition unavailable');
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
      _snack('음성 입력을 사용할 수 없습니다. 마이크 권한을 확인해 주세요.');
    }
  }

  String _responseLanguage() {
    return switch (_language) {
      'en' => 'English',
      'ja' => 'Japanese',
      'zh' => 'Simplified Chinese',
      _ => 'Korean',
    };
  }

  Future<List<Uint8List>> _readImageBytes() async {
    final result = <Uint8List>[];
    for (final image in _images) {
      result.add(await image.readAsBytes());
    }
    return result;
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty && _images.isEmpty) return;

    final apiKey = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (apiKey.isEmpty) {
      _snack('설정에서 Gemini API 키를 먼저 입력하세요.');
      setState(() => _tab = 2);
      return;
    }

    List<Uint8List> imageBytes;
    try {
      imageBytes = await _readImageBytes();
    } catch (error) {
      await _log('image_read', error);
      _snack('선택한 사진 중 일부를 읽지 못했습니다. 해당 사진을 삭제하고 다시 추가해 주세요.');
      return;
    }

    final userText = text.isEmpty ? '사진 ${imageBytes.length}장을 하나의 자료로 종합 분석해 주세요.' : text;
    setState(() {
      _messages.add(ChatEntry(role: 'user', text: userText, images: imageBytes));
      _input.clear();
      _images.clear();
      _busy = true;
    });
    _scrollToBottom();

    try {
      final recordContext = _records.take(30).map((r) => r.toJson()).toList();
      final parts = <Map<String, dynamic>>[
        {
          'text': '''You are an AI-first personal health record assistant.
Reply in ${_responseLanguage()}.
Analyze text, OCR-visible content, and all attached images together.
Do not diagnose or change medication. Clearly separate confirmed facts from estimates.
You can classify records into: vitals, body, meal, medication, symptom, activity, medical_history, document, hospital_schedule, prevention, unknown.
For save candidates, finish with one JSON code block exactly like:
```json
{"intent":"save|query|update|delete|question","items":[{"category":"vitals","type":"blood_glucose","summary":"공복 혈당 126 mg/dL","occurredAt":"2026-07-23T08:00:00","confidence":0.95}]}
```
If the user asks to retrieve records, use this local record context and summarize relevant entries:
${jsonEncode(recordContext)}
User input: $userText''',
        },
      ];
      for (final bytes in imageBytes) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(bytes),
          }
        });
      }

      final response = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode({
              'contents': [
                {'role': 'user', 'parts': parts}
              ],
              'generationConfig': {'temperature': 0.2},
            }),
          )
          .timeout(const Duration(seconds: 75));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = response.body.length > 500 ? response.body.substring(0, 500) : response.body;
        throw HttpExceptionInfo(response.statusCode, detail);
      }

      final answer = _extractGeminiText(response.body);
      if (!mounted) return;
      setState(() => _messages.add(ChatEntry(role: 'assistant', text: answer)));
      await _offerRecordSave(answer, imageBytes.isEmpty ? 'chat' : 'image');
    } on HttpExceptionInfo catch (error) {
      await _log('gemini_http_${error.statusCode}', error);
      _addFriendlyError(_friendlyHttpMessage(error.statusCode));
    } on FormatException catch (error) {
      await _log('gemini_response_parse', error);
      _addFriendlyError('AI 응답을 읽는 중 오류가 발생했습니다. 다시 시도하거나 오류 로그를 복사해 주세요.');
    } catch (error) {
      await _log('gemini_network', error);
      _addFriendlyError('인터넷 또는 Gemini 서버에 연결하지 못했습니다. 네트워크를 확인한 뒤 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  String _extractGeminiText(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Root is not an object');
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) throw const FormatException('No candidates');
    final first = candidates.first;
    if (first is! Map<String, dynamic>) throw const FormatException('Invalid candidate');
    final content = first['content'];
    if (content is! Map<String, dynamic>) throw const FormatException('Invalid content');
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) throw const FormatException('No parts');
    final texts = parts
        .whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .where((text) => text.isNotEmpty)
        .toList();
    if (texts.isEmpty) throw const FormatException('No text');
    return texts.join('\n');
  }

  String _friendlyHttpMessage(int statusCode) {
    return switch (statusCode) {
      400 => '요청 형식이 올바르지 않습니다. 사진 수나 입력 내용을 줄여 다시 시도해 주세요.',
      401 || 403 => 'Gemini API 키가 올바르지 않거나 사용 권한이 없습니다. 설정에서 키를 확인해 주세요.',
      404 => '현재 Gemini 모델을 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      429 => 'API 사용량이 많아 잠시 제한되었습니다. 잠시 후 다시 시도해 주세요.',
      >= 500 => 'Gemini 서버에 일시적인 문제가 있습니다. 잠시 후 다시 시도해 주세요.',
      _ => 'Gemini 요청이 실패했습니다. 오류 로그에서 상태 코드를 확인해 주세요.',
    };
  }

  void _addFriendlyError(String text) {
    if (!mounted) return;
    setState(() => _messages.add(ChatEntry(role: 'assistant', text: text)));
  }

  Future<void> _offerRecordSave(String answer, String inputMethod) async {
    final match = RegExp(r'```json\s*([\s\S]*?)```', caseSensitive: false).firstMatch(answer);
    if (match == null) return;
    try {
      final parsed = jsonDecode(match.group(1)!.trim());
      if (parsed is! Map<String, dynamic>) return;
      final intent = parsed['intent']?.toString() ?? '';
      final rawItems = parsed['items'];
      if (intent != 'save' || rawItems is! List || rawItems.isEmpty || !mounted) return;

      final candidates = rawItems.whereType<Map>().map((item) {
        final occurred = DateTime.tryParse(item['occurredAt']?.toString() ?? '') ?? DateTime.now();
        return HealthRecord(
          id: DateTime.now().microsecondsSinceEpoch.toString() + item.hashCode.toString(),
          category: item['category']?.toString() ?? 'unknown',
          type: item['type']?.toString() ?? 'unknown',
          summary: item['summary']?.toString() ?? '',
          occurredAt: occurred,
          inputMethod: inputMethod,
          confidence: (item['confidence'] as num?)?.toDouble() ?? 0.0,
        );
      }).where((record) => record.summary.isNotEmpty).toList();
      if (candidates.isEmpty) return;

      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('분석 결과를 저장할까요?'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = candidates[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.summary),
                  subtitle: Text('${item.category} · 신뢰도 ${(item.confidence * 100).round()}%'),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('save'))),
          ],
        ),
      );
      if (save == true) {
        _records.insertAll(0, candidates);
        await _persist();
        if (mounted) setState(() {});
        _snack('${candidates.length}개 기록을 저장했습니다.');
      }
    } catch (error) {
      await _log('record_candidate_parse', error);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _editApiKey() async {
    final current = await _secureStorage.read(key: 'gemini_api_key') ?? '';
    final controller = TextEditingController(text: current);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('api')),
        content: TextField(
          controller: controller,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'API key',
            helperText: '키는 Android 보안 저장소에 저장됩니다.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) {
                await _secureStorage.delete(key: 'gemini_api_key');
              } else {
                await _secureStorage.write(key: 'gemini_api_key', value: value);
              }
              if (context.mounted) Navigator.pop(context);
              _snack(value.isEmpty ? 'API 키를 삭제했습니다.' : 'API 키를 저장했습니다.');
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _testApi() async {
    final apiKey = (await _secureStorage.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (apiKey.isEmpty) {
      _snack('먼저 API 키를 입력하세요.');
      return;
    }
    try {
      final response = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': 'Reply only: OK'}
                  ]
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _snack('Gemini API 연결에 성공했습니다.');
      } else {
        throw HttpExceptionInfo(response.statusCode, response.body);
      }
    } catch (error) {
      await _log('api_test', error);
      _snack('연결 테스트에 실패했습니다. 오류 로그를 확인해 주세요.');
    }
  }

  Future<void> _changeLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', value);
    if (!mounted) return;
    setState(() => _language = value);
    widget.onLanguageChanged(value);
  }

  Future<void> _copyLogs() async {
    final text = _logs
        .map((log) => '${log.time.toLocal()}\n단계: ${log.stage}\n오류: ${log.message}')
        .join('\n\n---\n\n');
    await Clipboard.setData(ClipboardData(text: text.isEmpty ? '오류 로그 없음' : text));
    _snack('오류 로그를 복사했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('title'), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(t('subtitle'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildChat(),
          _buildRecords(),
          _buildSettings(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.auto_awesome), label: t('chat')),
          NavigationDestination(icon: const Icon(Icons.folder_copy_outlined), label: t('records')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: t('settings')),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.health_and_safety_outlined, size: 64),
                          const SizedBox(height: 16),
                          Text(t('empty'), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _messageBubble(_messages[index]),
                  ),
          ),
          if (_images.isNotEmpty) _imageQueue(),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _messageBubble(ChatEntry entry) {
    final mine = entry.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.images.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.images
                    .map((bytes) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(bytes, width: 92, height: 92, fit: BoxFit.cover),
                        ))
                    .toList(),
              ),
            if (entry.images.isNotEmpty) const SizedBox(height: 8),
            SelectableText(entry.text),
          ],
        ),
      ),
    );
  }

  Widget _imageQueue() {
    return SizedBox(
      height: 132,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: _images.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _images.removeAt(oldIndex);
            _images.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final image = _images[index];
          return Container(
            key: ValueKey('${image.path}-$index'),
            width: 112,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                Expanded(
                  child: FutureBuilder<Uint8List>(
                    future: image.readAsBytes(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      return InkWell(
                        onTap: () => _previewImage(index),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          child: Image.memory(snapshot.data!, width: double.infinity, fit: BoxFit.cover),
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: '다시 촬영',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _takePhoto(replaceIndex: index),
                      icon: const Icon(Icons.cameraswitch_outlined, size: 19),
                    ),
                    IconButton(
                      tooltip: t('delete'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _images.removeAt(index)),
                      icon: const Icon(Icons.delete_outline, size: 19),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _inputBar() {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (value) {
                if (value == 'gallery') _pickImages();
                if (value == 'camera') _takePhoto();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('갤러리 여러 장'))),
                PopupMenuItem(value: 'camera', child: ListTile(leading: Icon(Icons.camera_alt_outlined), title: Text('카메라 연속 촬영'))),
              ],
            ),
            IconButton(
              onPressed: _toggleSpeech,
              icon: Icon(_listening ? Icons.mic : Icons.mic_none),
              color: _listening ? Colors.red : null,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: t('hint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecords() {
    if (_records.isEmpty) {
      return const Center(child: Text('저장된 건강기록이 없습니다.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _records[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.favorite_outline)),
            title: Text(item.summary),
            subtitle: Text('${item.category} · ${item.type}\n${item.occurredAt.toLocal()}'),
            isThreeLine: true,
            trailing: IconButton(
              onPressed: () async {
                setState(() => _records.removeAt(index));
                await _persist();
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(t('api')),
                subtitle: const Text('Android 보안 저장소에 저장'),
                onTap: _editApiKey,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.network_check),
                title: Text(t('test')),
                onTap: _testApi,
              ),
            ],
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.language),
            title: Text(t('language')),
            trailing: DropdownButton<String>(
              value: _language,
              onChanged: (value) {
                if (value != null) _changeLanguage(value);
              },
              items: [
                DropdownMenuItem(value: 'system', child: Text(t('system'))),
                const DropdownMenuItem(value: 'ko', child: Text('한국어')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'ja', child: Text('日本語')),
                const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
              ],
            ),
          ),
        ),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(t('logs')),
            subtitle: Text('${_logs.length}개'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _copyLogs, icon: const Icon(Icons.copy), label: Text(t('copy')))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _logs.isEmpty
                            ? null
                            : () async {
                                setState(() => _logs.clear());
                                await _persist();
                              },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(t('delete')),
                      ),
                    ),
                  ],
                ),
              ),
              ..._logs.take(20).map(
                    (log) => ListTile(
                      title: Text(log.stage),
                      subtitle: Text('${log.time.toLocal()}\n${log.message}', maxLines: 5, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                    ),
                  ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '의료 응급상황에서는 앱의 답변을 기다리지 말고 즉시 119 또는 가까운 응급실에 연락하세요.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class HttpExceptionInfo implements Exception {
  HttpExceptionInfo(this.statusCode, this.detail);
  final int statusCode;
  final String detail;

  @override
  String toString() => 'HTTP $statusCode: $detail';
}
