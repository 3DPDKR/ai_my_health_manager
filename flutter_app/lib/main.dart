import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthApp());
}

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '나의 건강관리',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF159447)),
        scaffoldBackgroundColor: const Color(0xFFF6FAF7),
      ),
      home: const MainShell(),
    );
  }
}

class ChatItem {
  ChatItem({required this.role, required this.text});
  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
  factory ChatItem.fromJson(Map<String, dynamic> json) =>
      ChatItem(role: json['role'] as String, text: json['text'] as String);
}

class HealthRecord {
  HealthRecord({required this.title, required this.value, required this.unit});
  final String title;
  final String value;
  final String unit;

  Map<String, dynamic> toJson() => {'title': title, 'value': value, 'unit': unit};
  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        title: json['title'] as String,
        value: json['value'] as String,
        unit: json['unit'] as String,
      );
}

class GeminiService {
  static const _model = 'gemini-2.5-flash';

  Future<String> ask({
    required String apiKey,
    required String question,
    required List<HealthRecord> records,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('더보기에서 Gemini API 키를 먼저 저장해 주세요.');
    }

    final context = records
        .take(20)
        .map((e) => '- ${e.title}: ${e.value}${e.unit}')
        .join('\n');

    final prompt = '''
당신은 한국어 건강관리 기록 보조 AI입니다.
최근 건강 기록을 참고해 이해하기 쉽게 답변하세요.
진단을 확정하거나 약 변경·중단을 지시하지 마세요.
흉통, 호흡곤란, 의식 변화, 얼굴 처짐, 말 어눌함, 한쪽 마비,
갑작스러운 심한 두통이나 시야 이상은 즉시 119 또는 응급실 안내를 우선하세요.
답변은 간결한 한국어로 작성하세요.

최근 기록:
${context.isEmpty ? '저장된 기록 없음' : context}

사용자 질문:
$question
''';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
    );
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey.trim(),
      },
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 1000}
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Gemini 연결 오류 ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    final parts = candidates?.firstOrNull?['content']?['parts'] as List<dynamic>?;
    final text = parts
        ?.map((e) => e['text']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .join('\n');
    return (text == null || text.isEmpty) ? '답변을 받지 못했습니다.' : text;
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  String apiKey = '';
  bool loading = false;
  final chats = <ChatItem>[];
  final records = <HealthRecord>[];
  final gemini = GeminiService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final chatRaw = prefs.getString('chats');
    final recordRaw = prefs.getString('records');
    setState(() {
      apiKey = prefs.getString('gemini_api_key') ?? '';
      if (chatRaw != null) {
        chats.addAll((jsonDecode(chatRaw) as List)
            .map((e) => ChatItem.fromJson(Map<String, dynamic>.from(e))));
      }
      if (recordRaw != null) {
        records.addAll((jsonDecode(recordRaw) as List)
            .map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e))));
      }
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chats', jsonEncode(chats.map((e) => e.toJson()).toList()));
    await prefs.setString('records', jsonEncode(records.map((e) => e.toJson()).toList()));
  }

  Future<void> send(String question) async {
    if (question.trim().isEmpty || loading) return;
    setState(() {
      chats.add(ChatItem(role: 'user', text: question.trim()));
      loading = true;
    });
    await _persist();
    try {
      final answer = await gemini.ask(
        apiKey: apiKey,
        question: question.trim(),
        records: records,
      );
      setState(() => chats.add(ChatItem(role: 'ai', text: answer)));
    } catch (e) {
      setState(() => chats.add(ChatItem(role: 'ai', text: e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      setState(() => loading = false);
      await _persist();
    }
  }

  Future<void> saveKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', value.trim());
    setState(() => apiKey = value.trim());
  }

  Future<void> addGlucose(String value) async {
    if (value.isEmpty) return;
    setState(() => records.insert(0, HealthRecord(title: '혈당', value: value, unit: ' mg/dL')));
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(chats: chats, loading: loading, onSend: send, onOpenChat: () => setState(() => index = 2), onAddGlucose: addGlucose),
      RecordsPage(records: records),
      ChatPage(chats: chats, loading: loading, onSend: send),
      const SchedulePage(),
      SettingsPage(initialKey: apiKey, onSave: saveKey),
    ];

    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: '기록'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI 대화'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '일정'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: '더보기'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.chats, required this.loading, required this.onSend, required this.onOpenChat, required this.onAddGlucose});
  final List<ChatItem> chats;
  final bool loading;
  final Future<void> Function(String) onSend;
  final VoidCallback onOpenChat;
  final Future<void> Function(String) onAddGlucose;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final chat = TextEditingController();
  final glucose = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final recent = widget.chats.length <= 4 ? widget.chats : widget.chats.sublist(widget.chats.length - 4);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('나의 건강관리', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(DateFormat('yyyy년 M월 d일 EEEE', 'ko').format(DateTime.now())),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(children: [
                  const Icon(Icons.smart_toy),
                  const SizedBox(width: 8),
                  const Text('AI 건강 대화', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  const Spacer(),
                  TextButton(onPressed: widget.onOpenChat, child: const Text('전체보기')),
                ]),
                if (recent.isEmpty)
                  const Align(alignment: Alignment.centerLeft, child: Text('약, 병원 일정, 혈당, 식단이나 운동을 바로 물어보세요.')),
                ...recent.map((m) => Align(
                      alignment: m.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 310),
                        decoration: BoxDecoration(
                          color: m.role == 'user' ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(m.text),
                      ),
                    )),
                if (widget.loading) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: chat, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '건강 기록이나 질문 입력'))),
                  IconButton(onPressed: widget.loading ? null : () { final v = chat.text; chat.clear(); widget.onSend(v); }, icon: const Icon(Icons.send)),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Card(child: ListTile(title: Text('오늘 해야 할 일', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('✓ 아침 복약 확인\n○ 혈당 측정\n○ 20분 걷기'))),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('빠른 혈당 기록', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: glucose, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'mg/dL'))),
                const SizedBox(width: 8),
                FilledButton(onPressed: () { final v = glucose.text; glucose.clear(); widget.onAddGlucose(v); }, child: const Text('저장')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        const Card(child: ListTile(leading: Icon(Icons.favorite_outline), title: Text('오늘의 건강 제안', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('식후 무리하지 않는 범위에서 가볍게 걸어 보세요.'))),
      ],
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.chats, required this.loading, required this.onSend});
  final List<ChatItem> chats;
  final bool loading;
  final Future<void> Function(String) onSend;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const ListTile(title: Text('AI 건강 대화', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)), subtitle: Text('저장된 건강 기록을 참고해 답변합니다.')),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: widget.chats.length,
        itemBuilder: (_, i) {
          final m = widget.chats[i];
          return Align(
            alignment: m.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxWidth: 330),
              decoration: BoxDecoration(color: m.role == 'user' ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Text(m.text),
            ),
          );
        },
      )),
      if (widget.loading) const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: TextField(controller: input, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '메시지를 입력하세요'))),
          IconButton(onPressed: widget.loading ? null : () { final v = input.text; input.clear(); widget.onSend(v); }, icon: const Icon(Icons.send)),
        ]),
      ),
    ]);
  }
}

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key, required this.records});
  final List<HealthRecord> records;

  @override
  Widget build(BuildContext context) => Column(children: [
        const ListTile(title: Text('건강 기록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))),
        Expanded(child: records.isEmpty
            ? const Center(child: Text('아직 저장된 기록이 없습니다.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: records.length,
                itemBuilder: (_, i) => Card(child: ListTile(leading: const Icon(Icons.monitor_heart_outlined), title: Text(records[i].title), subtitle: Text('${records[i].value}${records[i].unit}'))),
              )),
      ]);
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) => const ListView(padding: EdgeInsets.all(16), children: [
        Text('일정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        SizedBox(height: 12),
        Card(child: ListTile(leading: Icon(Icons.local_hospital_outlined), title: Text('병원 일정'), subtitle: Text('저장된 예약 일정이 여기에 표시됩니다.'))),
        Card(child: ListTile(leading: Icon(Icons.medication_outlined), title: Text('복약 일정'), subtitle: Text('복약 알림과 완료 기록이 여기에 표시됩니다.'))),
      ]);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initialKey, required this.onSave});
  final String initialKey;
  final Future<void> Function(String) onSave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController key;
  bool hidden = true;

  @override
  void initState() {
    super.initState();
    key = TextEditingController(text: widget.initialKey);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('더보기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Gemini API 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const Text('키는 이 기기의 앱 저장소에 보관됩니다.'),
              const SizedBox(height: 10),
              TextField(
                controller: key,
                obscureText: hidden,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Gemini API 키',
                  suffixIcon: IconButton(onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility : Icons.visibility_off)),
                ),
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () async { await widget.onSave(key.text); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 키가 저장되었습니다.'))); }, child: const Text('저장'))),
            ]),
          ),
        ),
        const Card(child: ListTile(leading: Icon(Icons.security), title: Text('보안 안내'), subtitle: Text('채팅에 공개된 키는 새 키로 재발급한 뒤 사용하는 것을 권장합니다.'))),
      ]);
}
