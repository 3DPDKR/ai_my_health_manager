import 'package:flutter/material.dart';

void main() {
  runApp(const HealthManagerApp());
}

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
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int currentIndex = 0;
  final List<HealthEntry> entries = <HealthEntry>[];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(onAdd: _openAddDialog, entries: entries),
      RecordsPage(entries: entries),
      const AiPage(),
      const SchedulePage(),
      const MorePage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (value) => setState(() => currentIndex = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: '기록'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '일정'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: '더보기'),
        ],
      ),
      floatingActionButton: currentIndex == 0 || currentIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('건강 기록'),
            )
          : null,
    );
  }

  Future<void> _openAddDialog() async {
    final typeController = TextEditingController(text: '혈당');
    final valueController = TextEditingController();
    final result = await showDialog<HealthEntry>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('건강 기록 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: typeController,
              decoration: const InputDecoration(labelText: '항목', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(labelText: '값', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (valueController.text.trim().isEmpty) return;
              Navigator.pop(
                dialogContext,
                HealthEntry(typeController.text.trim(), valueController.text.trim(), DateTime.now()),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() => entries.insert(0, result));
    }
  }
}

class HealthEntry {
  HealthEntry(this.type, this.value, this.createdAt);
  final String type;
  final String value;
  final DateTime createdAt;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onAdd, required this.entries});
  final VoidCallback onAdd;
  final List<HealthEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('나의 건강관리', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('오늘의 건강 상태를 간단하게 확인하세요.'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.task_alt),
                    SizedBox(width: 8),
                    Text('오늘 할 일', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('• 아침 복약 확인'),
                const Text('• 혈당 또는 혈압 기록'),
                const Text('• 가벼운 걷기 20분'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.smart_toy)),
            title: const Text('AI 건강 도우미'),
            subtitle: const Text('건강 기록을 정리하고 병원 방문 전 질문을 준비합니다.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI 기능은 다음 버전에서 연결됩니다.'))),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_chart), label: const Text('빠른 건강 기록')),
        const SizedBox(height: 18),
        Text('최근 기록', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Card(child: ListTile(title: Text('아직 저장된 기록이 없습니다.'), subtitle: Text('아래 버튼으로 첫 기록을 추가하세요.')))
        else
          ...entries.take(3).map((entry) => Card(
                child: ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: Text(entry.type),
                  subtitle: Text(entry.createdAt.toString().substring(0, 16)),
                  trailing: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
      ],
    );
  }
}

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key, required this.entries});
  final List<HealthEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('건강 기록', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('저장된 건강 기록이 없습니다.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.monitor_heart),
                        title: Text(entry.type),
                        subtitle: Text(entry.createdAt.toString().substring(0, 16)),
                        trailing: Text(entry.value),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class AiPage extends StatelessWidget {
  const AiPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        Text('AI 건강 도우미', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('건강 기록 요약, 복약 확인, 병원 방문 준비 기능을 순차적으로 연결합니다.\n\n응급 증상이 의심되면 앱 답변보다 119 또는 응급실 안내를 우선합니다.'),
          ),
        ),
      ],
    );
  }
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        Text('건강 일정', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        Card(child: ListTile(leading: Icon(Icons.medication), title: Text('복약 일정'), subtitle: Text('아침 · 저녁 복약을 확인하세요.'))),
        Card(child: ListTile(leading: Icon(Icons.local_hospital), title: Text('병원 일정'), subtitle: Text('등록된 병원 예약이 여기에 표시됩니다.'))),
      ],
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        Text('더보기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        Card(child: ListTile(leading: Icon(Icons.settings), title: Text('앱 설정'))),
        Card(child: ListTile(leading: Icon(Icons.security), title: Text('개인정보 및 보안'))),
        Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('앱 정보'), subtitle: Text('나의 건강관리 1.0.0'))),
      ],
    );
  }
}
