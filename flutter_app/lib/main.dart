import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() => runApp(const HealthApp());

class HealthApp extends StatefulWidget {
  const HealthApp({super.key});
  @override
  State<HealthApp> createState() => _HealthAppState();
}

class _HealthAppState extends State<HealthApp> {
  String language = 'system';
  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }
  Future<void> _loadLanguage() async {
    final p = await SharedPreferences.getInstance();
    setState(() => language = p.getString('language') ?? 'system');
  }
  Locale? get locale {
    switch (language) {
      case 'ko': return const Locale('ko');
      case 'en': return const Locale('en');
      case 'ja': return const Locale('ja');
      case 'zh': return const Locale('zh');
      default: return null;
    }
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AI 건강비서',
    locale: locale,
    supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja'), Locale('zh')],
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16864B))),
    home: MainScreen(onLanguageChanged: (v) => setState(() => language = v)),
  );
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
  Map<String, dynamic> toJson() => {'category': category, 'summary': summary, 'createdAt': createdAt.toIso8601String()};
  factory SavedItem.fromJson(Map<String, dynamic> j) => SavedItem(
    category: j['category'] ?? 'unknown', summary: j['summary'] ?? '', createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now());
}

class AppLog {
  AppLog({required this.time, required this.stage, required this.message});
  final DateTime time;
  final String stage;
  final String message;
  Map<String, dynamic> toJson() => {'time': time.toIso8601String(), 'stage': stage, 'message': message};
  factory AppLog.fromJson(Map<String, dynamic> j) => AppLog(
    time: DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(), stage: j['stage'] ?? '', message: j['message'] ?? '');
  String format() => '${time.toLocal()}\n단계: $stage\n오류: $message';
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.onLanguageChanged});
  final ValueChanged<String> onLanguageChanged;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _secure = FlutterSecureStorage();
  final _picker = ImagePicker();
  final _speech = stt.SpeechToText();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<XFile> _selected = [];
  final List<SavedItem> _items = [];
  final List<AppLog> _logs = [];
  int _tab = 0;
  bool _busy = false;
  bool _listening = false;
  String _language = 'system';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _language = p.getString('language') ?? 'system';
    try {
      _items.addAll((jsonDecode(p.getString('saved_items') ?? '[]') as List).map((e) => SavedItem.fromJson(Map<String,dynamic>.from(e))));
      _logs.addAll((jsonDecode(p.getString('app_logs') ?? '[]') as List).map((e) => AppLog.fromJson(Map<String,dynamic>.from(e))));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('saved_items', jsonEncode(_items.map((e) => e.toJson()).toList()));
    await p.setString('app_logs', jsonEncode(_logs.take(100).map((e) => e.toJson()).toList()));
  }

  Future<void> _log(String stage, Object error) async {
    final safe = error.toString().replaceAll(RegExp(r'AQ\.[A-Za-z0-9_\-]+'), '[API_KEY_HIDDEN]');
    _logs.insert(0, AppLog(time: DateTime.now(), stage: stage, message: safe));
    if (_logs.length > 100) _logs.removeRange(100, _logs.length);
    await _persist();
  }

  String _languageName() {
    switch (_language) {
      case 'en': return 'English';
      case 'ja': return 'Japanese';
      case 'zh': return 'Simplified Chinese';
      default: return 'Korean';
    }
  }

  Future<void> _pickMultiple() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 72, maxWidth: 1600);
      if (files.isEmpty) return;
      final remain = 5 - _selected.length;
      if (remain <= 0) {
        _toast('사진은 최대 5장까지 선택할 수 있습니다.');
        return;
      }
      setState(() => _selected.addAll(files.take(remain)));
      if (files.length > remain) _toast('최대 5장까지만 추가했습니다.');
    } catch (e) {
      await _log('사진 여러 장 선택', e);
      _toast('사진을 불러오지 못했습니다.');
    }
  }

  Future<void> _takePhoto() async {
    if (_selected.length >= 5) {
      _toast('사진은 최대 5장까지 추가할 수 있습니다.');
      return;
    }
    try {
      final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 72, maxWidth: 1600);
      if (file != null) setState(() => _selected.add(file));
    } catch (e) {
      await _log('카메라 촬영', e);
      _toast('카메라를 사용할 수 없습니다.');
    }
  }

  Future<void> _toggleSpeech() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    try {
      final ok = await _speech.initialize();
      if (!ok) throw Exception('음성 인식을 시작할 수 없습니다.');
      setState(() => _listening = true);
      await _speech.listen(
        localeId: _language == 'system' ? null : {'ko':'ko_KR','en':'en_US','ja':'ja_JP','zh':'zh_CN'}[_language],
        onResult: (r) => setState(() => _input.text = r.recognizedWords),
      );
    } catch (e) {
      await _log('음성 입력', e);
      _toast('음성 입력을 사용할 수 없습니다.');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _selected.isEmpty) return;
    final key = (await _secure.read(key: 'gemini_api_key'))?.trim() ?? '';
    if (key.isEmpty) {
      _toast('설정에서 Gemini API 키를 먼저 입력하세요.');
      setState(() => _tab = 2);
      return;
    }
    final images = <Uint8List>[];
    for (final f in _selected) { images.add(await f.readAsBytes()); }
    setState(() {
      _messages.add(ChatMessage(role: 'user', text: text.isEmpty ? '사진 ${images.length}장 분석' : text, images: images));
      _input.clear();
      _selected.clear();
      _busy = true;
    });
    try {
      final parts = <Map<String,dynamic>>[
        {'text': '''당신은 개인 건강기록 정리 도우미입니다. 사용자의 자연어와 첨부 사진을 함께 분석하세요.
응답 언어: ${_languageName()}.
다음 분류 중 하나 이상으로 정리하세요: vitals, body, meal, medication, symptom, activity, medical_history, document, hospital_schedule, prevention, unknown.
확정 정보와 추정 정보를 구분하고, 의료 진단이나 약 변경 지시는 하지 마세요.
마지막에 반드시 아래 JSON 블록을 포함하세요.
```json
{"items":[{"category":"분류","summary":"저장할 핵심 내용"}]}
```
사용자 입력: ${text.isEmpty ? '첨부된 사진들을 하나의 자료 묶음으로 종합 분석해 주세요.' : text}'''}
      ];
      for (var i=0; i<images.length; i++) {
        parts.add({'inline_data': {'mime_type': _selectedMime(i), 'data': base64Encode(images[i])}});
      }
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
        headers: {'Content-Type':'application/json','x-goog-api-key':key},
        body: jsonEncode({'contents':[{'parts':parts}], 'generationConfig':{'temperature':0.2}}),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Gemini HTTP ${response.statusCode}: ${response.body.length > 300 ? response.body.substring(0,300) : response.body}');
      }
      final data = jsonDecode(response.body);
      final answer = data['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '응답을 읽지 못했습니다.';
      setState(() => _messages.add(ChatMessage(role: 'assistant', text: answer)));
      _offerSave(answer);
    } catch (e) {
      await _log('Gemini 분석', e);
      setState(() => _messages.add(ChatMessage(role:'assistant', text:'분석에 실패했습니다. 인터넷 연결과 API 키를 확인하세요. 설정의 오류 로그에서 자세한 내용을 복사할 수 있습니다.')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollBottom();
    }
  }

  String _selectedMime(int index) => 'image/jpeg';

  Future<void> _offerSave(String answer) async {
    final match = RegExp(r'```json\s*(\{[\s\S]*?\})\s*```').firstMatch(answer);
    if (match == null) return;
    try {
      final obj = jsonDecode(match.group(1)!);
      final list = (obj['items'] as List? ?? []);
      if (list.isEmpty || !mounted) return;
      final save = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('분석 결과 저장'),
        content: Text('${list.length}개 항목을 건강 데이터로 저장할까요?\n저장 후 기록 화면에서 다시 불러올 수 있습니다.'),
        actions: [TextButton(onPressed:()=>Navigator.pop(c,false), child: const Text('취소')), FilledButton(onPressed:()=>Navigator.pop(c,true), child: const Text('저장'))],
      ));
      if (save == true) {
        for (final raw in list) {
          final m = Map<String,dynamic>.from(raw);
          _items.insert(0, SavedItem(category:m['category'] ?? 'unknown', summary:m['summary'] ?? '', createdAt:DateTime.now()));
        }
        await _persist();
        setState(() {});
      }
    } catch (e) { await _log('분석 결과 저장', e); }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds:250), curve:Curves.easeOut);
    });
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: [_chatPage(), _recordsPage(), _settingsPage()][_tab]),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (v) => setState(() => _tab=v),
      destinations: const [
        NavigationDestination(icon:Icon(Icons.auto_awesome_outlined), selectedIcon:Icon(Icons.auto_awesome), label:'AI 건강비서'),
        NavigationDestination(icon:Icon(Icons.folder_outlined), selectedIcon:Icon(Icons.folder), label:'저장 기록'),
        NavigationDestination(icon:Icon(Icons.settings_outlined), selectedIcon:Icon(Icons.settings), label:'설정'),
      ],
    ),
  );

  Widget _chatPage() => Column(children:[
    const ListTile(title:Text('AI 건강비서', style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)), subtitle:Text('대화·사진·촬영·음성으로 입력하세요')),
    Expanded(child:_messages.isEmpty ? const Center(child:Padding(padding:EdgeInsets.all(32), child:Text('예: “오늘 공복 혈당 126이야”\n처방전이나 약봉투 사진은 최대 5장까지 한 번에 분석할 수 있습니다.', textAlign:TextAlign.center))) : ListView.builder(
      controller:_scroll, padding:const EdgeInsets.all(12), itemCount:_messages.length, itemBuilder:(c,i){
        final m=_messages[i]; final user=m.role=='user';
        return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft, child:Container(
          margin:const EdgeInsets.symmetric(vertical:6), padding:const EdgeInsets.all(12), constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*.85),
          decoration:BoxDecoration(color:user?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(18)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            if(m.images.isNotEmpty) SizedBox(height:90, child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:m.images.length,separatorBuilder:(_,__)=>const SizedBox(width:6),itemBuilder:(_,j)=>ClipRRect(borderRadius:BorderRadius.circular(10),child:Image.memory(m.images[j],width:90,height:90,fit:BoxFit.cover)))),
            if(m.images.isNotEmpty) const SizedBox(height:8), SelectableText(m.text),
          ]),
        ));
      })),
    if(_selected.isNotEmpty) SizedBox(height:92, child:ListView.builder(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),itemCount:_selected.length,itemBuilder:(c,i)=>FutureBuilder<Uint8List>(future:_selected[i].readAsBytes(),builder:(c,s)=>Stack(children:[
      Container(margin:const EdgeInsets.only(right:8),width:82,height:82,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),color:Colors.black12),child:s.hasData?ClipRRect(borderRadius:BorderRadius.circular(12),child:Image.memory(s.data!,fit:BoxFit.cover)):const Center(child:CircularProgressIndicator())),
      Positioned(right:4,top:0,child:IconButton.filledTonal(icon:const Icon(Icons.close,size:16),onPressed:()=>setState(()=>_selected.removeAt(i)))),
    ])))),
    if(_selected.isNotEmpty) Padding(padding:const EdgeInsets.symmetric(horizontal:14), child:Align(alignment:Alignment.centerLeft,child:Text('선택된 사진 ${_selected.length}/5장'))),
    Padding(padding:const EdgeInsets.fromLTRB(8,6,8,10),child:Row(children:[
      PopupMenuButton<String>(icon:const Icon(Icons.add_circle_outline),onSelected:(v){if(v=='gallery')_pickMultiple();else _takePhoto();},itemBuilder:(_)=>const [PopupMenuItem(value:'gallery',child:Text('사진 여러 장 선택')),PopupMenuItem(value:'camera',child:Text('카메라 촬영'))]),
      IconButton(icon:Icon(_listening?Icons.mic:Icons.mic_none),onPressed:_toggleSpeech),
      Expanded(child:TextField(controller:_input,minLines:1,maxLines:4,decoration:const InputDecoration(hintText:'건강 내용을 편하게 입력하세요',border:OutlineInputBorder()))),
      IconButton(icon:_busy?const SizedBox(width:22,height:22,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send),onPressed:_busy?null:_send),
    ])),
  ]);

  Widget _recordsPage() => Column(children:[
    const ListTile(title:Text('저장 기록',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),subtitle:Text('AI 분석 후 확인하여 저장한 데이터')),
    Expanded(child:_items.isEmpty?const Center(child:Text('저장된 기록이 없습니다.')):ListView.builder(padding:const EdgeInsets.all(12),itemCount:_items.length,itemBuilder:(c,i){final e=_items[i];return Card(child:ListTile(leading:const Icon(Icons.health_and_safety_outlined),title:Text(e.category),subtitle:Text('${e.summary}\n${e.createdAt.toLocal()}'),isThreeLine:true,trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>_items.removeAt(i));await _persist();})));})),
  ]);

  Widget _settingsPage() => ListView(padding:const EdgeInsets.all(16),children:[
    const Text('설정',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),const SizedBox(height:12),
    Card(child:ListTile(leading:const Icon(Icons.key),title:const Text('Gemini API 키'),subtitle:const Text('기기에 안전하게 저장하고 연결을 확인합니다.'),onTap:_apiDialog)),
    Card(child:ListTile(leading:const Icon(Icons.language),title:const Text('언어'),subtitle:Text(_languageLabel(_language)),onTap:_languageDialog)),
    Card(child:ListTile(leading:const Icon(Icons.bug_report_outlined),title:const Text('오류 로그'),subtitle:Text('${_logs.length}개 저장됨 · 복사 및 AI 분석 가능'),onTap:_logsDialog)),
    const Card(child:ListTile(leading:Icon(Icons.photo_library_outlined),title:Text('사진 분석'),subtitle:Text('한 번에 최대 5장'))),
    Card(child:ListTile(leading:const Icon(Icons.delete_forever_outlined),title:const Text('모든 건강 기록 삭제'),onTap:()async{setState(()=>_items.clear());await _persist();})),
    const Card(child:ListTile(leading:Icon(Icons.info_outline),title:Text('앱 정보'),subtitle:Text('AI 건강비서 2.1.0 · MCP/카카오 공모전 기능 없음'))),
  ]);

  String _languageLabel(String v)=>{'system':'시스템 설정 따름','ko':'한국어','en':'English','ja':'日本語','zh':'简体中文'}[v]??v;

  Future<void> _languageDialog() async {
    final v=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:const Text('언어 선택'),children:['system','ko','en','ja','zh'].map((e)=>RadioListTile<String>(value:e,groupValue:_language,title:Text(_languageLabel(e)),onChanged:(x)=>Navigator.pop(c,x))).toList()));
    if(v!=null){final p=await SharedPreferences.getInstance();await p.setString('language',v);setState(()=>_language=v);widget.onLanguageChanged(v);}
  }

  Future<void> _apiDialog() async {
    final current=await _secure.read(key:'gemini_api_key')??'';
    final c=TextEditingController(text:current);
    if(!mounted)return;
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Gemini API 키'),content:TextField(controller:c,obscureText:true,decoration:const InputDecoration(labelText:'API 키',border:OutlineInputBorder())),actions:[
      TextButton(onPressed:()async{await _secure.delete(key:'gemini_api_key');if(ctx.mounted)Navigator.pop(ctx);},child:const Text('삭제')),
      TextButton(onPressed:()async{final key=c.text.trim();if(key.isEmpty)return;try{final r=await http.post(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),headers:{'Content-Type':'application/json','x-goog-api-key':key},body:jsonEncode({'contents':[{'parts':[{'text':'reply OK'}]}]})).timeout(const Duration(seconds:20));if(r.statusCode>=200&&r.statusCode<300){_toast('API 연결 성공');}else{throw Exception('HTTP ${r.statusCode}');}}catch(e){await _log('API 연결 테스트',e);_toast('연결 실패. 오류 로그를 확인하세요.');}},child:const Text('연결 테스트')),
      FilledButton(onPressed:()async{await _secure.write(key:'gemini_api_key',value:c.text.trim());if(ctx.mounted)Navigator.pop(ctx);},child:const Text('저장')),
    ]));
  }

  Future<void> _logsDialog() async {
    if(!mounted)return;
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('오류 로그'),content:SizedBox(width:double.maxFinite,height:420,child:_logs.isEmpty?const Center(child:Text('저장된 오류가 없습니다.')):ListView.separated(itemCount:_logs.length,separatorBuilder:(_,__)=>const Divider(),itemBuilder:(_,i)=>SelectableText(_logs[i].format()))),actions:[
      TextButton(onPressed:()async{final text=_logs.map((e)=>e.format()).join('\n\n---\n\n');await Clipboard.setData(ClipboardData(text:text));_toast('오류 로그를 복사했습니다.');},child:const Text('전체 복사')),
      TextButton(onPressed:()async{final text=_logs.take(10).map((e)=>e.format()).join('\n\n');Navigator.pop(ctx);setState((){_tab=0;_input.text='아래 앱 오류 로그를 분석해서 원인과 해결 순서를 알려줘.\n\n$text';});},child:const Text('AI로 분석')),
      TextButton(onPressed:()async{setState(()=>_logs.clear());await _persist();if(ctx.mounted)Navigator.pop(ctx);},child:const Text('삭제')),
      FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('닫기')),
    ]));
  }
}
