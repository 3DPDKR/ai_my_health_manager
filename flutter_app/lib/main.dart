import 'package:flutter/material.dart';

void main() => runApp(const HealthManagerApp());

class HealthManagerApp extends StatelessWidget {
  const HealthManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '나의 건강관리',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16864B)),
        scaffoldBackgroundColor: const Color(0xFFF5F8F5),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const MainPage(),
    );
  }
}

class HealthEntry {
  HealthEntry(this.type, this.value, this.createdAt);
  final String type;
  final String value;
  final DateTime createdAt;
}

class ScheduleEntry {
  ScheduleEntry(this.kind, this.title, this.detail);
  final String kind;
  final String title;
  final String detail;
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int index = 0;
  final List<HealthEntry> records = [];
  final List<ScheduleEntry> schedules = [];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Home(records: records, schedules: schedules, onRecord: _addRecord, onSchedule: _addSchedule, onMove: (v) => setState(() => index = v)),
      _Records(records: records, onAdd: _addRecord),
      const _AiPage(),
      _Schedules(entries: schedules, onAdd: _addSchedule),
      const _MorePage(),
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
    String type = '혈당';
    final value = TextEditingController();
    final result = await showDialog<HealthEntry>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) => AlertDialog(
        title: const Text('건강 기록 추가'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: '항목'),
            items: const ['혈당', '혈압', '체중', '체온', '산소포화도', '증상'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setLocal(() => type = v ?? type),
          ),
          const SizedBox(height: 12),
          TextField(controller: value, decoration: const InputDecoration(labelText: '측정값 또는 내용')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
          FilledButton(onPressed: () {
            if (value.text.trim().isEmpty) return;
            Navigator.pop(c, HealthEntry(type, value.text.trim(), DateTime.now()));
          }, child: const Text('저장')),
        ],
      )),
    );
    if (result != null) setState(() => records.insert(0, result));
  }

  Future<void> _addSchedule() async {
    String kind = '병원';
    final title = TextEditingController();
    final detail = TextEditingController();
    final result = await showDialog<ScheduleEntry>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) => AlertDialog(
        title: const Text('건강 일정 추가'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: '종류'),
            items: const ['병원', '복약', '검사', '기타'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setLocal(() => kind = v ?? kind),
          ),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: const InputDecoration(labelText: '제목')),
          const SizedBox(height: 12),
          TextField(controller: detail, decoration: const InputDecoration(labelText: '날짜·시간·메모')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
          FilledButton(onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(c, ScheduleEntry(kind, title.text.trim(), detail.text.trim()));
          }, child: const Text('저장')),
        ],
      )),
    );
    if (result != null) setState(() => schedules.insert(0, result));
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
  );
}

class _Home extends StatelessWidget {
  const _Home({required this.records, required this.schedules, required this.onRecord, required this.onSchedule, required this.onMove});
  final List<HealthEntry> records;
  final List<ScheduleEntry> schedules;
  final VoidCallback onRecord;
  final VoidCallback onSchedule;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.only(bottom: 24), children: [
    const _Header('나의 건강관리', '내가 입력하고 확인한 정보만 안전하게 관리합니다.'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('빠른 등록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: onRecord, icon: const Icon(Icons.add_chart), label: const Text('건강 기록'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: onSchedule, icon: const Icon(Icons.event), label: const Text('일정 등록'))),
        ]),
      ]),
    ))),
    const SizedBox(height: 8),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.document_scanner_outlined)),
      title: const Text('사진·문서 분석'),
      subtitle: const Text('처방전, 약봉투, 검사표, 음식 사진을 분석한 뒤 확인하여 저장합니다.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onMove(2),
    ))),
    Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 6), child: Text('최근 기록', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
    if (records.isEmpty)
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Card(child: ListTile(title: Text('등록된 건강 기록이 없습니다.'), subtitle: Text('측정값이나 증상을 직접 등록해 주세요.'))))
    else
      ...records.take(3).map((e) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(child: ListTile(leading: const Icon(Icons.favorite_outline), title: Text(e.type), trailing: Text(e.value), subtitle: Text(_time(e.createdAt))))))),
    Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 6), child: Text('다가오는 일정', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
    if (schedules.isEmpty)
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Card(child: ListTile(title: Text('등록된 병원·복약 일정이 없습니다.'), subtitle: Text('기본으로 입력되는 개인 일정은 없습니다.'))))
    else
      ...schedules.take(3).map((e) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(child: ListTile(leading: const Icon(Icons.event_note), title: Text(e.title), subtitle: Text('${e.kind} · ${e.detail}'))))),
  ]);
}

class _Records extends StatelessWidget {
  const _Records({required this.records, required this.onAdd});
  final List<HealthEntry> records;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Column(children: [
    const _Header('건강 기록', '혈당, 혈압, 체중, 체온과 증상을 기록합니다.'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('기록 추가')))),
    const SizedBox(height: 8),
    Expanded(child: records.isEmpty
      ? const Center(child: Text('저장된 건강 기록이 없습니다.'))
      : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: records.length, itemBuilder: (c, i) {
          final e = records[i];
          return Card(child: ListTile(leading: const Icon(Icons.monitor_heart), title: Text(e.type), subtitle: Text(_time(e.createdAt)), trailing: Text(e.value, style: const TextStyle(fontWeight: FontWeight.bold))));
        })),
  ]);
}

class _AiPage extends StatelessWidget {
  const _AiPage();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    const _Header('AI 자료 분석', '자료를 분석한 뒤 반드시 확인하고 저장합니다.'),
    ...[
      ('처방전·약봉투', '약 이름, 복용 시간과 횟수를 정리합니다.', Icons.medication_outlined),
      ('병원 예약 안내', '병원명, 진료과, 날짜와 시간을 정리합니다.', Icons.local_hospital_outlined),
      ('검사표·측정기', '건강 수치를 읽어 기록 초안을 만듭니다.', Icons.biotech_outlined),
      ('음식 사진', '음식 종류와 식사 내용을 정리합니다.', Icons.restaurant_outlined),
    ].map((e) => Card(child: ListTile(leading: CircleAvatar(child: Icon(e.$3)), title: Text(e.$1), subtitle: Text(e.$2), trailing: const Icon(Icons.chevron_right), onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('사진 선택과 Gemini 분석 기능은 API 인증 설정 후 사용할 수 있습니다.'))))),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('분석 결과는 자동 저장하지 않습니다.\n확인 → 수정 → 저장 순서로 적용합니다.\n\n갑작스러운 마비, 심한 흉통, 호흡곤란 등 응급 증상은 앱보다 119와 응급실 안내를 우선하세요.'))),
  ]);
}

class _Schedules extends StatelessWidget {
  const _Schedules({required this.entries, required this.onAdd});
  final List<ScheduleEntry> entries;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Column(children: [
    const _Header('건강 일정', '병원, 복약, 검사 일정을 직접 등록합니다.'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('일정 추가')))),
    const SizedBox(height: 8),
    Expanded(child: entries.isEmpty
      ? const Center(child: Text('등록된 일정이 없습니다.'))
      : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: entries.length, itemBuilder: (c, i) {
          final e = entries[i];
          return Card(child: ListTile(leading: Icon(e.kind == '복약' ? Icons.medication : Icons.event), title: Text(e.title), subtitle: Text('${e.kind} · ${e.detail}')));
        })),
  ]);
}

class _MorePage extends StatelessWidget {
  const _MorePage();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: const [
    _Header('더보기', '설정과 앱 정보를 확인합니다.'),
    Card(child: ListTile(leading: Icon(Icons.security_outlined), title: Text('개인정보 원칙'), subtitle: Text('사용자가 확인하고 저장한 정보만 관리'))),
    Card(child: ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('MCP 연동'), subtitle: Text('사용하지 않음'))),
    Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('앱 정보'), subtitle: Text('나의 건강관리 1.1.0'))),
  ]);
}

String _time(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
