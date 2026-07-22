import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const HealthApp());

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI Health Manager',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16864B)),
          scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        ),
        home: const HealthHome(),
      );
}

class HealthRecord {
  HealthRecord({required this.category, required this.type, required this.value, required this.unit, required this.time, required this.source});
  final String category;
  final String type;
  final String value;
  final String unit;
  final String time;
  final String source;
  Map<String, dynamic> toJson() => {'category': category, 'type': type, 'value': value, 'unit': unit, 'time': time, 'source': source};
  factory HealthRecord.fromJson(Map<String, dynamic> j) => HealthRecord(
        category: '${j['category'] ?? 'unknown'}',
        type: '${j['type'] ?? ''}',
        value: '${j['value'] ?? ''}',
        unit: '${j['unit'] ?? ''}',
        time: '${j['time'] ?? ''}',
        source: '${j['source'] ?? 'chat'}',
      );
}

class ChatMessage {
  ChatMessage(this.text, this.mine, {this.image});
  final String text;
  final bool mine;
  final Uint8List? image;
}

class HealthHome extends StatefulWidget {
  const HealthHome({super.key});
  @override
  State<HealthHome> createState() => _HealthHomeState();
}

class _HealthHomeState extends State<HealthHome> {
  static const _secure = FlutterSecureStorage();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _speech = SpeechToText();
  final List<ChatMessage> _messages = [];
  final List<HealthRecord> _records = [];

  int _tab = 0;
  bool _busy = false;
  bool _listening = false;
  Uint8List? _pendingImage;
  String _pendingMime = 'image/jpeg';
  String _language = 'system';

  static const Map<String, Map<String, String>> _texts = {
    'ko': {
      'app': 'AI 건강비서', 'records': '건강 기록', 'settings': '설정', 'chat': 'AI 대화',
      'hello': '안녕하세요. 건강 관련 내용을 편하게 말씀하거나 사진을 올려주세요. 분석 후 저장 전 반드시 확인받겠습니다.',
      'hint': '건강 내용을 편하게 입력하세요', 'camera': '카메라 촬영', 'gallery': '사진 선택',
      'apiMissing': 'Gemini API 키가 없습니다. 설정에서 API 키를 입력한 뒤 다시 시도해 주세요.',
      'saveTitle': '분석 결과 저장 확인', 'cancel': '취소', 'save': '저장', 'saved': '개 항목을 건강 기록에 저장했습니다.',
      'empty': '저장된 건강 기록이 없습니다.', 'api': 'Gemini API 키', 'apiHint': 'API 키 입력',
      'apiSave': 'API 키 저장', 'apiDelete': 'API 키 삭제', 'language': '언어', 'system': '시스템 설정 따름',
      'privacy': '사용자가 확인한 내용만 저장합니다.', 'reset': '모든 건강 기록 삭제', 'confirmReset': '모든 기록을 삭제할까요?',
      'error': '분석 중 오류가 발생했습니다. API 키와 인터넷 연결을 확인해 주세요.',
    },
    'en': {
      'app': 'AI Health Assistant', 'records': 'Health Records', 'settings': 'Settings', 'chat': 'AI Chat',
      'hello': 'Tell me about your health or attach a photo. I will ask for confirmation before saving anything.',
      'hint': 'Type health information naturally', 'camera': 'Take photo', 'gallery': 'Choose photo',
      'apiMissing': 'No Gemini API key. Add one in Settings and try again.',
      'saveTitle': 'Confirm records to save', 'cancel': 'Cancel', 'save': 'Save', 'saved': ' record(s) saved.',
      'empty': 'No saved health records.', 'api': 'Gemini API Key', 'apiHint': 'Enter API key',
      'apiSave': 'Save API Key', 'apiDelete': 'Delete API Key', 'language': 'Language', 'system': 'Use system language',
      'privacy': 'Only confirmed information is saved.', 'reset': 'Delete all health records', 'confirmReset': 'Delete all records?',
      'error': 'Analysis failed. Check the API key and internet connection.',
    },
    'ja': {
      'app': 'AI健康アシスタント', 'records': '健康記録', 'settings': '設定', 'chat': 'AIチャット',
      'hello': '健康について話すか、写真を添付してください。保存前に必ず確認します。',
      'hint': '健康内容を自然に入力してください', 'camera': 'カメラ撮影', 'gallery': '写真を選択',
      'apiMissing': 'Gemini APIキーがありません。設定で入力してください。',
      'saveTitle': '保存内容の確認', 'cancel': 'キャンセル', 'save': '保存', 'saved': '件を保存しました。',
      'empty': '保存された健康記録はありません。', 'api': 'Gemini APIキー', 'apiHint': 'APIキーを入力',
      'apiSave': 'APIキーを保存', 'apiDelete': 'APIキーを削除', 'language': '言語', 'system': 'システム言語を使用',
      'privacy': '確認した内容だけ保存します。', 'reset': 'すべての健康記録を削除', 'confirmReset': 'すべての記録を削除しますか？',
      'error': '分析中にエラーが発生しました。APIキーと接続を確認してください。',
    },
    'zh': {
      'app': 'AI健康助手', 'records': '健康记录', 'settings': '设置', 'chat': 'AI对话',
      'hello': '请直接描述健康情况或上传照片。保存前会先向您确认。',
      'hint': '自然输入健康信息', 'camera': '拍照', 'gallery': '选择照片',
      'apiMissing': '没有Gemini API密钥。请在设置中输入。',
      'saveTitle': '确认保存内容', 'cancel': '取消', 'save': '保存', 'saved': '条记录已保存。',
      'empty': '暂无健康记录。', 'api': 'Gemini API密钥', 'apiHint': '输入API密钥',
      'apiSave': '保存API密钥', 'apiDelete': '删除API密钥', 'language': '语言', 'system': '跟随系统语言',
      'privacy': '仅保存您确认的信息。', 'reset': '删除所有健康记录', 'confirmReset': '删除所有记录吗？',
      'error': '分析失败。请检查API密钥和网络。',
    },
  };

  String get _langCode {
    if (_language != 'system') return _language;
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    return _texts.containsKey(code) ? code : 'en';
  }

  String t(String key) => _texts[_langCode]?[key] ?? _texts['en']![key] ?? key;

  String get _geminiLanguage => {'ko': 'Korean', 'en': 'English', 'ja': 'Japanese', 'zh': 'Simplified Chinese'}[_langCode] ?? 'English';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _language = p.getString('language') ?? 'system';
    try {
      final raw = jsonDecode(p.getString('health_records') ?? '[]') as List;
      _records.addAll(raw.map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e))));
    } catch (_) {}
    _messages.add(ChatMessage(t('hello'), false));
    if (mounted) setState(() {});
  }

  Future<void> _saveRecords() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('health_records', jsonEncode(_records.map((e) => e.toJson()).toList()));
  }

  Future<String> _apiKey() async {
    const built = String.fromEnvironment('GEMINI_API_KEY');
    if (built.isNotEmpty) return built;
    return await _secure.read(key: 'gemini_api_key') ?? '';
  }

  Future<void> _pick(ImageSource source) async {
    final f = await _picker.pickImage(source: source, imageQuality: 78, maxWidth: 1800);
    if (f == null) return;
    _pendingImage = await f.readAsBytes();
    _pendingMime = f.mimeType ?? 'image/jpeg';
    setState(() {});
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize();
    if (!ok) return;
    setState(() => _listening = true);
    final locale = {'ko': 'ko_KR', 'en': 'en_US', 'ja': 'ja_JP', 'zh': 'zh_CN'}[_langCode];
    await _speech.listen(localeId: locale, onResult: (r) {
      setState(() => _input.text = r.recognizedWords);
      if (r.finalResult) setState(() => _listening = false);
    });
  }

  String _recordsContext() => jsonEncode(_records.take(50).map((e) => e.toJson()).toList());

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _pendingImage == null) return;
    final image = _pendingImage;
    final mime = _pendingMime;
    setState(() {
      _messages.add(ChatMessage(text.isEmpty ? 'Photo analysis' : text, true, image: image));
      _input.clear();
      _pendingImage = null;
      _busy = true;
    });
    _jump();

    final key = await _apiKey();
    if (key.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(t('apiMissing'), false));
        _busy = false;
        _tab = 2;
      });
      return;
    }

    try {
      final instruction = '''You are a personal health data assistant. Respond in $_geminiLanguage.
Analyze chat, photo or transcribed speech. Supported categories: vitals, body, meal, medication, symptom, activity, medical_history, document, hospital_schedule, prevention, unknown.
Use the saved records below when the user asks to retrieve or summarize past data: ${_recordsContext()}
Never save automatically. New candidate records must be returned in records for user confirmation. For emergency warning signs, advise emergency services first.
Return one JSON object only:
{"reply":"answer for user","records":[{"category":"vitals","type":"blood_glucose","value":"128","unit":"mg/dL","time":"ISO or user expression","source":"chat|photo|voice"}]}
Use an empty records array when nothing should be saved.''';
      final parts = <Map<String, dynamic>>[
        {'text': '$instruction\n\nUser input: ${text.isEmpty ? 'Analyze attached photo' : text}'}
      ];
      if (image != null) {
        parts.add({'inline_data': {'mime_type': mime, 'data': base64Encode(image)}});
      }
      final res = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
        body: jsonEncode({'contents': [{'parts': parts}], 'generationConfig': {'temperature': 0.15, 'responseMimeType': 'application/json'}}),
      ).timeout(const Duration(seconds: 60));
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('API ${res.statusCode}');
      final outer = jsonDecode(res.body);
      final raw = outer['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '{}';
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final reply = '${parsed['reply'] ?? ''}';
      final drafts = ((parsed['records'] ?? []) as List)
          .map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        _messages.add(ChatMessage(reply, false));
        _busy = false;
      });
      if (drafts.isNotEmpty && mounted) await _confirmSave(drafts);
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage('${t('error')}\n$e', false));
        _busy = false;
      });
    }
    _jump();
  }

  Future<void> _confirmSave(List<HealthRecord> drafts) async {
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('saveTitle')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: drafts
                .map((r) => ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(r.type.isEmpty ? r.category : r.type),
                      subtitle: Text('${r.value}${r.unit.isEmpty ? '' : ' ${r.unit}'}\n${r.time}'),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('save'))),
        ],
      ),
    );
    if (save == true) {
      setState(() {
        _records.insertAll(0, drafts);
        _messages.add(ChatMessage('${drafts.length}${t('saved')}', false));
      });
      await _saveRecords();
    }
  }

  void _jump() => Future.delayed(const Duration(milliseconds: 120), () {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final pages = [_chatPage(), _recordPage(), _settingsPage()];
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? t('app') : _tab == 1 ? t('records') : t('settings'))),
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), selectedIcon: const Icon(Icons.chat_bubble), label: t('chat')),
          NavigationDestination(icon: const Icon(Icons.folder_copy_outlined), selectedIcon: const Icon(Icons.folder_copy), label: t('records')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: t('settings')),
        ],
      ),
    );
  }

  Widget _chatPage() => Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(14),
            itemCount: _messages.length,
            itemBuilder: (c, i) {
              final m = _messages[i];
              return Align(
                alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: m.mine ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (m.image != null) ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(m.image!, height: 170, fit: BoxFit.cover)),
                    if (m.image != null) const SizedBox(height: 8),
                    Text(m.text),
                  ]),
                ),
              );
            },
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_pendingImage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_pendingImage!, width: 58, height: 58, fit: BoxFit.cover)),
              const SizedBox(width: 8),
              Expanded(child: Text(t('gallery'))),
              IconButton(onPressed: () => setState(() => _pendingImage = null), icon: const Icon(Icons.close)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (v) => _pick(v == 'camera' ? ImageSource.camera : ImageSource.gallery),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'camera', child: Text(t('camera'))),
                PopupMenuItem(value: 'gallery', child: Text(t('gallery'))),
              ],
            ),
            IconButton(onPressed: _busy ? null : _toggleVoice, icon: Icon(_listening ? Icons.mic : Icons.mic_none)),
            Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: t('hint'), border: const OutlineInputBorder()))),
            IconButton(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
          ]),
        ),
      ]);

  Widget _recordPage() => _records.isEmpty
      ? Center(child: Text(t('empty')))
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _records.length,
          itemBuilder: (_, i) {
            final r = _records[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.monitor_heart_outlined)),
                title: Text(r.type.isEmpty ? r.category : r.type),
                subtitle: Text('${r.category} · ${r.time} · ${r.source}'),
                trailing: Text('${r.value}${r.unit.isEmpty ? '' : ' ${r.unit}'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          },
        );

  Widget _settingsPage() {
    final keyController = TextEditingController();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: Text(t('privacy')))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('language'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _language,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: 'system', child: Text(t('system'))),
                const DropdownMenuItem(value: 'ko', child: Text('한국어')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'ja', child: Text('日本語')),
                const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                final p = await SharedPreferences.getInstance();
                await p.setString('language', v);
                setState(() => _language = v);
              },
            ),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('api'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: keyController, obscureText: true, decoration: InputDecoration(hintText: t('apiHint'), border: const OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final value = keyController.text.trim();
                if (value.isNotEmpty) await _secure.write(key: 'gemini_api_key', value: value);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('apiSave'))));
              },
              child: Text(t('apiSave')),
            ),
            TextButton(
              onPressed: () async {
                await _secure.delete(key: 'gemini_api_key');
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('apiDelete'))));
              },
              child: Text(t('apiDelete')),
            ),
          ]),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(t('reset')),
          onTap: () async {
            final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
              title: Text(t('confirmReset')),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('save')))],
            ));
            if (ok == true) {
              _records.clear();
              await _saveRecords();
              setState(() {});
            }
          },
        ),
      ),
      const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('AI My Health Manager'), subtitle: Text('2.0.0'))),
    ]);
  }
}
