import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
      home: const HomeShell(),
    );
  }
}

class ChatMessage {
  ChatMessage(this.role, this.text);
  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      json['role']?.toString() ?? 'ai',
      json['text']?.toString() ?? '',
    );
  }
}

class GeminiApi {
  Future<String> ask(String apiKey, String prompt) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('더보기에서 Gemini API 키를 먼저 저장해 주세요.');
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
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
              {
                'text': '''
당신은 한국어 건강관리 기록 보조 AI입니다.
쉽고 간결하게 답변하세요.
질병을 확정 진단하거나 약 변경·중단을 지시하지 마세요.
얼굴 처짐, 말 어눌함, 한쪽 마비, 심한 흉통, 호흡곤란,
의식 변화, 갑작스러운 극심한 두통이 있으면 119 또는 응급실을 우선 안내하세요.

사용자 질문: $prompt
'''
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 1000,
        }
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Gemini 연결 오류 ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Gemini 응답 형식 오류');
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return '답변을 받지 못했습니다.';
    }

    final first = candidates.first;
    if (first is! Map<String, dynamic>) return '답변을 받지 못했습니다.';
    final content = first['content'];
    if (content is! Map<String, dynamic>) return '답변을 받지 못했습니다.';
    final parts = content['parts'];
    if (parts is! List) return '답변을 받지 못했습니다.';

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map<String, dynamic>) {
        final text = part['text'];
        if (text != null) buffer.writeln(text.toString());
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? '답변을 받지 못했습니다.' : result;
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GeminiApi gemini = GeminiApi();
  final List<ChatMessage> messages = <ChatMessage>[];
  final List<String> glucoseRecords = <String>[];
  int pageIndex = 0;
  bool loading = false;
  String apiKey = '';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final chatJson = prefs.getString('chat_history');
    final savedGlucose = prefs.getStringList('glucose_records') ?? <String>[];

    final loadedMessages = <ChatMessage>[];
    if (chatJson != null && chatJson.isNotEmpty) {
      final decoded = jsonDecode(chatJson);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            loadedMessages.add(ChatMessage.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      apiKey = prefs.getString('gemini_api_key') ?? '';
      messages
        ..clear()
        ..addAll(loadedMessages);
      glucoseRecords
        ..clear()
        ..addAll(savedGlucose);
    });
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'chat_history',
      jsonEncode(messages.map((item) => item.toJson()).toList()),
    );
    await prefs.setStringList('glucose_records', glucoseRecords);
  }

  Future<void> sendMessage(String value) async {
    final question = value.trim();
    if (question.isEmpty || loading) return;

    setState(() {
      messages.add(ChatMessage('user', question));
      loading = true;
    });
    await saveData();

    try {
      final answer = await gemini.ask(apiKey, question);
      if (!mounted) return;
      setState(() => messages.add(ChatMessage('ai', answer)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        messages.add(
          ChatMessage('ai', error.toString().replaceFirst('Exception: ', '')),
        );
      });
    } finally {
      if (mounted) setState(() => loading = false);
      await saveData();
    }
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    if (!mounted) return;
    setState(() => apiKey = key.trim());
  }

  Future<void> addGlucose(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) return;
    setState(() => glucoseRecords.insert(0, '$clean mg/dL'));
    await saveData();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(
        messages: messages,
        loading: loading,
        onSend: sendMessage,
        onOpenChat: () => setState(() => pageIndex = 2),
        onAddGlucose: addGlucose,
      ),
      RecordsPage(records: glucoseRecords),
      ChatPage(messages: messages, loading: loading, onSend: sendMessage),
      const SchedulePage(),
      SettingsPage(initialKey: apiKey, onSave: saveApiKey),
    ];

    return Scaffold(
      body: SafeArea(child: pages[pageIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: pageIndex,
        onDestinationSelected: (value) => setState(() => pageIndex = value),
        destinations: const <NavigationDestination>[
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
  const DashboardPage({super.key, required this.messages, required this.loading, required this.onSend, required this.onOpenChat, required this.onAddGlucose});
  final List<ChatMessage> messages;
  final bool loading;
  final Future<void> Function(String) onSend;
  final VoidCallback onOpenChat;
  final Future<void> Function(String) onAddGlucose;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TextEditingController chatController = TextEditingController();
  final TextEditingController glucoseController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final start = widget.messages.length > 4 ? widget.messages.length - 4 : 0;
    final recent = widget.messages.sublist(start);
    final today = DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('나의 건강관리', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text('${today.year}년 ${today.month}월 ${today.day}일'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: <Widget>[
                Row(children: <Widget>[
                  const Icon(Icons.smart_toy),
                  const SizedBox(width: 8),
                  const Text('AI 건강 대화', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  const Spacer(),
                  TextButton(onPressed: widget.onOpenChat, child: const Text('전체보기')),
                ]),
                if (recent.isEmpty)
                  const Align(alignment: Alignment.centerLeft, child: Text('약, 병원 일정, 혈당, 식단이나 운동을 바로 물어보세요.')),
                for (final message in recent) ChatBubble(message: message),
                if (widget.loading) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  Expanded(child: TextField(controller: chatController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '건강 기록이나 질문 입력'))),
                  IconButton(
                    onPressed: widget.loading ? null : () {
                      final value = chatController.text;
                      chatController.clear();
                      widget.onSend(value);
                    },
                    icon: const Icon(Icons.send),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const Card(child: ListTile(title: Text('오늘 해야 할 일', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('✓ 아침 복약 확인\n○ 혈당 측정\n○ 20분 걷기'))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Text('빠른 혈당 기록', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(child: TextField(controller: glucoseController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'mg/dL'))),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final value = glucoseController.text;
                    glucoseController.clear();
                    widget.onAddGlucose(value);
                  },
                  child: const Text('저장'),
                ),
              ]),
            ]),
          ),
        ),
        const Card(child: ListTile(leading: Icon(Icons.favorite_outline), title: Text('오늘의 건강 제안', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('식후 무리하지 않는 범위에서 가볍게 걸어 보세요.'))),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(11),
        constraints: const BoxConstraints(maxWidth: 330),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(message.text),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.messages, required this.loading, required this.onSend});
  final List<ChatMessage> messages;
  final bool loading;
  final Future<void> Function(String) onSend;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      const ListTile(title: Text('AI 건강 대화', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)), subtitle: Text('건강 관련 질문을 바로 입력하세요.')),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: <Widget>[for (final message in widget.messages) ChatBubble(message: message)],
        ),
      ),
      if (widget.loading) const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: <Widget>[
          Expanded(child: TextField(controller: controller, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '메시지를 입력하세요'))),
          IconButton(
            onPressed: widget.loading ? null : () {
              final value = controller.text;
              controller.clear();
              widget.onSend(value);
            },
            icon: const Icon(Icons.send),
          ),
        ]),
      ),
    ]);
  }
}

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key, required this.records});
  final List<String> records;

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      const ListTile(title: Text('건강 기록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22))),
      Expanded(
        child: records.isEmpty
            ? const Center(child: Text('아직 저장된 기록이 없습니다.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: records.length,
                itemBuilder: (context, index) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.monitor_heart_outlined),
                    title: const Text('혈당'),
                    subtitle: Text(records[index]),
                  ),
                ),
              ),
      ),
    ]);
  }
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListView(
      padding: EdgeInsets.all(16),
      children: <Widget>[
        Text('일정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        SizedBox(height: 12),
        Card(child: ListTile(leading: Icon(Icons.local_hospital_outlined), title: Text('병원 일정'), subtitle: Text('저장된 병원 예약 일정이 표시됩니다.'))),
        Card(child: ListTile(leading: Icon(Icons.medication_outlined), title: Text('복약 일정'), subtitle: Text('복약 알림과 완료 기록이 표시됩니다.'))),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initialKey, required this.onSave});
  final String initialKey;
  final Future<void> Function(String) onSave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController controller;
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialKey);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('더보기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Text('Gemini API 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const Text('API 키는 이 기기의 앱 저장소에 보관됩니다.'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                obscureText: obscure,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Gemini API 키',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    await widget.onSave(controller.text);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 키가 저장되었습니다.')));
                  },
                  child: const Text('저장'),
                ),
              ),
            ]),
          ),
        ),
        const Card(child: ListTile(leading: Icon(Icons.security), title: Text('보안 안내'), subtitle: Text('채팅에 공개된 API 키는 재발급 후 사용하는 것을 권장합니다.'))),
      ],
    );
  }
}
