import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const HealthApp());

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '나의 건강관리',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16864b)),
          scaffoldBackgroundColor: const Color(0xfff4f7f5),
        ),
        home: const AppShell(),
      );
}

class HealthItem {
  HealthItem(this.kind, this.value, this.time);
  final String kind;
  final String value;
  final DateTime time;
  Map<String, dynamic> toJson() => {'kind': kind, 'value': value, 'time': time.toIso8601String()};
  factory HealthItem.fromJson(Map<String, dynamic> j) => HealthItem(
      j['kind'] ?? '', j['value'] ?? '', DateTime.tryParse(j['time'] ?? '') ?? DateTime.now());
}

class PlanItem {
  PlanItem(this.title, this.detail, this.category, {this.done = false});
  final String title;
  final String detail;
  final String category;
  bool done;
  Map<String, dynamic> toJson() => {'title': title, 'detail': detail, 'category': category, 'done': done};
  factory PlanItem.fromJson(Map<String, dynamic> j) =>
      PlanItem(j['title'] ?? '', j['detail'] ?? '', j['category'] ?? '일정', done: j['done'] == true);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  bool loading = true;
  final records = <HealthItem>[];
  final plans = <PlanItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      records.addAll((jsonDecode(prefs.getString('records') ?? '[]') as List)
          .map((e) => HealthItem.fromJson(Map<String, dynamic>.from(e))));
      plans.addAll((jsonDecode(prefs.getString('plans') ?? '[]') as List)
          .map((e) => PlanItem.fromJson(Map<String, dynamic>.from(e))));
    } catch (_) {}
    if (plans.isEmpty) {
      plans.addAll([
        PlanItem('아침 복약', '아침 식후 복용', '복약'),
        PlanItem('저녁 복약', '저녁 식후 복용', '복약'),
        PlanItem('부산백병원 안과', '2026-11-12 14:00 · 3층 안과', '병원'),
      ]);
    }
    setState(() => loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('records', jsonEncode(records.map((e) => e.toJson()).toList()));
    await prefs.setString('plans', jsonEncode(plans.map((e) => e.toJson()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pages = [
      HomeTab(records: records, plans: plans, onAdd: _addRecord, onToggle: _togglePlan),
      RecordsTab(records: records, onAdd: _addRecord),
      const AiTab(),
      ScheduleTab(plans: plans, onAdd: _addPlan, onToggle: _togglePlan),
      MoreTab(onReset: _reset),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: '기록'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '일정'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: '더보기'),
        ],
      ),
    );
  }

  Future<void> _addRecord() async {
    String kind = '혈당';
    final value = TextEditingController();
    final result = await showDialog<HealthItem>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('건강 기록 추가'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: kind,
              decoration: const InputDecoration(labelText: '기록 종류', border: OutlineInputBorder()),
              items: const ['혈당', '혈압', '체중', '체온', '산소포화도', '증상', '식사', '운동']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setLocal(() => kind = v ?? kind),
            ),
            const SizedBox(height: 12),
            TextField(controller: value, decoration: const InputDecoration(labelText: '값 또는 내용', border: OutlineInputBorder())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
            FilledButton(onPressed: () {
              if (value.text.trim().isNotEmpty) Navigator.pop(c, HealthItem(kind, value.text.trim(), DateTime.now()));
            }, child: const Text('저장')),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() => records.insert(0, result));
      await _save();
    }
  }

  Future<void> _addPlan() async {
    final title = TextEditingController();
    final detail = TextEditingController();
    String category = '복약';
    final result = await showDialog<PlanItem>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('일정 추가'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: '분류'),
              items: const ['복약', '병원', '검사', '운동', '기타']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setLocal(() => category = v ?? category),
            ),
            TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
            TextField(controller: detail, decoration: const InputDecoration(labelText: '시간·설명')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
            FilledButton(onPressed: () {
              if (title.text.trim().isNotEmpty) Navigator.pop(c, PlanItem(title.text.trim(), detail.text.trim(), category));
            }, child: const Text('저장')),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() => plans.add(result));
      await _save();
    }
  }

  Future<void> _togglePlan(PlanItem item, bool value) async {
    setState(() => item.done = value);
    await _save();
  }

  Future<void> _reset() async {
    setState(() { records.clear(); plans.clear(); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        if (subtitle != null) Text(subtitle!),
      ]));
}

Widget recordTile(HealthItem e) => Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.favorite_outline)),
        title: Text(e.kind),
        subtitle: Text('${e.time.year}-${e.time.month.toString().padLeft(2, '0')}-${e.time.day.toString().padLeft(2, '0')} ${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}'),
        trailing: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 140), child: Text(e.value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
      ),
    );

class HomeTab extends StatelessWidget {
  const HomeTab({required this.records, required this.plans, required this.onAdd, required this.onToggle, super.key});
  final List<HealthItem> records;
  final List<PlanItem> plans;
  final VoidCallback onAdd;
  final void Function(PlanItem, bool) onToggle;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        const PageTitle('나의 건강관리', subtitle: '오늘 기록과 복약 일정을 한눈에 확인하세요.'),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('오늘 할 일', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...plans.take(3).map((p) => CheckboxListTile(contentPadding: EdgeInsets.zero, value: p.done, onChanged: (v) => onToggle(p, v ?? false), title: Text(p.title), subtitle: Text(p.detail), controlAffinity: ListTileControlAffinity.leading)),
        ]))),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_chart), label: const Text('건강 기록 추가')),
        const SizedBox(height: 12),
        const Text('최근 기록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (records.isEmpty) const Card(child: ListTile(title: Text('저장된 기록이 없습니다.'), subtitle: Text('혈당, 혈압, 체중 또는 증상을 기록해 보세요.'))),
        ...records.take(5).map(recordTile),
        Card(color: Theme.of(context).colorScheme.errorContainer, child: const ListTile(leading: Icon(Icons.emergency_outlined), title: Text('응급 신호'), subtitle: Text('갑작스러운 얼굴 마비, 말 어눌함, 한쪽 팔다리 힘 빠짐, 심한 흉통이 있으면 즉시 119에 연락하세요.'))),
      ]);
}

class RecordsTab extends StatelessWidget {
  const RecordsTab({required this.records, required this.onAdd, super.key});
  final List<HealthItem> records;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Column(children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: PageTitle('건강 기록', subtitle: '혈당·혈압·체중·증상을 저장합니다.')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('새 기록')))),
        Expanded(child: records.isEmpty ? const Center(child: Text('기록이 없습니다.')) : ListView(padding: const EdgeInsets.all(16), children: records.map(recordTile).toList())),
      ]);
}

class ScheduleTab extends StatelessWidget {
  const ScheduleTab({required this.plans, required this.onAdd, required this.onToggle, super.key});
  final List<PlanItem> plans;
  final VoidCallback onAdd;
  final void Function(PlanItem, bool) onToggle;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        const PageTitle('복약·병원 일정', subtitle: '완료한 일정은 체크해 주세요.'),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('일정 추가')),
        const SizedBox(height: 8),
        ...plans.map((p) => Card(child: CheckboxListTile(value: p.done, onChanged: (v) => onToggle(p, v ?? false), title: Text(p.title), subtitle: Text('${p.category} · ${p.detail}'), secondary: Icon(p.category == '병원' ? Icons.local_hospital : Icons.medication)))),
      ]);
}

class AiTab extends StatefulWidget {
  const AiTab({super.key});
  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');
  final prompt = TextEditingController();
  String answer = '';
  bool busy = false;
  Uint8List? image;
  String mime = 'image/jpeg';

  Future<void> pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
    if (file != null) {
      image = await file.readAsBytes();
      mime = file.mimeType ?? 'image/jpeg';
      setState(() {});
    }
  }

  Future<void> ask() async {
    if (apiKey.isEmpty) {
      setState(() => answer = 'Gemini API 키가 빌드에 연결되지 않았습니다.');
      return;
    }
    if (prompt.text.trim().isEmpty && image == null) return;
    setState(() => busy = true);
    try {
      final parts = <Map<String, dynamic>>[
        {'text': prompt.text.trim().isEmpty ? '이 건강 관련 사진을 한국어로 분석하고 확인된 내용과 추정 내용을 구분해 주세요. 처방전이면 약 이름과 복용법을 정리하고, 음식이면 예상 영양과 주의점을 정리해 주세요.' : prompt.text.trim()}
      ];
      if (image != null) parts.add({'inline_data': {'mime_type': mime, 'data': base64Encode(image!)}});
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: jsonEncode({'contents': [{'parts': parts}], 'generationConfig': {'temperature': 0.2}}),
      ).timeout(const Duration(seconds: 45));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        answer = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '응답을 읽지 못했습니다.';
      } else {
        answer = 'Gemini 연결 오류 (${response.statusCode})';
      }
    } catch (e) {
      answer = '분석 중 오류가 발생했습니다.\n$e';
    }
    setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('AI 건강 도우미', subtitle: '처방전·약봉투·식사 사진 또는 건강 질문을 분석합니다.'),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          TextField(controller: prompt, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: '예: 이 처방전의 약과 복용 방법을 정리해줘', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          if (image != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(image!, height: 180, fit: BoxFit.cover)),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: busy ? null : pick, icon: const Icon(Icons.photo_library_outlined), label: const Text('사진 선택'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: busy ? null : ask, icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome), label: const Text('분석'))),
          ]),
        ]))),
        if (answer.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(answer))),
        const Card(child: ListTile(leading: Icon(Icons.warning_amber), title: Text('의료 안전 안내'), subtitle: Text('AI 결과는 진단이 아닙니다. 약을 임의로 중단하거나 변경하지 말고, 응급 증상은 즉시 119 또는 응급실에 문의하세요.'))),
      ]);
}

class MoreTab extends StatelessWidget {
  const MoreTab({required this.onReset, super.key});
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('더보기'),
        const Card(child: ListTile(leading: Icon(Icons.lock_outline), title: Text('데이터 저장'), subtitle: Text('건강 기록과 일정은 현재 기기에 저장됩니다.'))),
        const Card(child: ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('MCP 미사용'), subtitle: Text('MCP 및 PlayMCP 연동은 포함하지 않았습니다.'))),
        const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('앱 정보'), subtitle: Text('나의 건강관리 1.1.0'))),
        Card(child: ListTile(leading: const Icon(Icons.delete_outline), title: const Text('모든 기록 초기화'), onTap: onReset)),
      ]);
}
