import 'package:flutter/material.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16864B)),
        scaffoldBackgroundColor: const Color(0xFFF5F8F5),
      ),
      home: const MainScreen(),
    );
  }
}

class HealthRecord {
  HealthRecord(this.type, this.value, this.time);
  final String type;
  final String value;
  final DateTime time;
}

class HealthSchedule {
  HealthSchedule(this.category, this.title, this.memo);
  final String category;
  final String title;
  final String memo;
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int pageIndex = 0;
  final List<HealthRecord> records = <HealthRecord>[];
  final List<HealthSchedule> schedules = <HealthSchedule>[];

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      _homePage(),
      _recordPage(),
      _aiPage(),
      _schedulePage(),
      _morePage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[pageIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: pageIndex,
        onDestinationSelected: (int value) {
          setState(() => pageIndex = value);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: '기록'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '일정'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: '더보기'),
        ],
      ),
    );
  }

  Widget _title(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle),
        ],
      ),
    );
  }

  Widget _homePage() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _title('나의 건강관리', '내가 확인하고 저장한 정보만 관리합니다.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('빠른 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _addRecord,
                      icon: const Icon(Icons.add_chart),
                      label: const Text('건강 기록 추가'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addSchedule,
                      icon: const Icon(Icons.event),
                      label: const Text('병원·복약 일정 추가'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text('최근 기록', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                title: Text('등록된 건강 기록이 없습니다.'),
                subtitle: Text('혈당, 혈압, 체중, 체온 또는 증상을 직접 등록해 주세요.'),
              ),
            ),
          )
        else
          ...records.take(3).map(_recordCard),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text('건강 일정', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (schedules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                title: Text('등록된 일정이 없습니다.'),
                subtitle: Text('기본으로 등록되는 병원이나 복약 일정은 없습니다.'),
              ),
            ),
          )
        else
          ...schedules.take(3).map(_scheduleCard),
      ],
    );
  }

  Widget _recordPage() {
    return Column(
      children: <Widget>[
        _title('건강 기록', '측정값과 증상을 직접 기록합니다.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: _addRecord, icon: const Icon(Icons.add), label: const Text('기록 추가')),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: records.isEmpty
              ? const Center(child: Text('저장된 건강 기록이 없습니다.'))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: records.map(_recordCard).toList(),
                ),
        ),
      ],
    );
  }

  Widget _aiPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _title('AI 자료 분석', '분석 결과를 확인하고 수정한 뒤 저장합니다.'),
        _analysisCard(Icons.medication_outlined, '처방전·약봉투', '약 이름과 복용 방법을 정리합니다.'),
        _analysisCard(Icons.local_hospital_outlined, '병원 예약 안내', '병원명, 진료과, 날짜와 시간을 정리합니다.'),
        _analysisCard(Icons.biotech_outlined, '검사표·측정기', '검사 수치와 측정값을 기록 초안으로 만듭니다.'),
        _analysisCard(Icons.restaurant_outlined, '음식 사진', '음식 종류와 식사 내용을 정리합니다.'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('분석 결과는 자동 저장하지 않습니다.\n확인 → 수정 → 저장 순서로 적용합니다.\n\n갑작스러운 마비, 심한 흉통, 호흡곤란은 앱보다 119 또는 응급실 안내를 우선하세요.'),
          ),
        ),
      ],
    );
  }

  Widget _schedulePage() {
    return Column(
      children: <Widget>[
        _title('건강 일정', '병원, 복약, 검사 일정을 직접 등록합니다.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: _addSchedule, icon: const Icon(Icons.add), label: const Text('일정 추가')),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: schedules.isEmpty
              ? const Center(child: Text('등록된 일정이 없습니다.'))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: schedules.map(_scheduleCard).toList(),
                ),
        ),
      ],
    );
  }

  Widget _morePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _title('더보기', '앱 설정과 정보를 확인합니다.'),
        const Card(child: ListTile(leading: Icon(Icons.security_outlined), title: Text('개인정보 원칙'), subtitle: Text('사용자가 확인하고 저장한 정보만 관리'))),
        const Card(child: ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('MCP 연동'), subtitle: Text('사용하지 않음'))),
        const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('앱 정보'), subtitle: Text('나의 건강관리 1.1.0'))),
      ],
    );
  }

  Widget _analysisCard(IconData icon, String title, String subtitle) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gemini API 인증과 사진 선택 기능 설정 후 사용할 수 있습니다.')),
          );
        },
      ),
    );
  }

  Widget _recordCard(HealthRecord record) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.monitor_heart),
          title: Text(record.type),
          subtitle: Text(_formatTime(record.time)),
          trailing: Text(record.value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _scheduleCard(HealthSchedule schedule) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: ListTile(
          leading: Icon(schedule.category == '복약' ? Icons.medication : Icons.event_note),
          title: Text(schedule.title),
          subtitle: Text('${schedule.category} · ${schedule.memo}'),
        ),
      ),
    );
  }

  Future<void> _addRecord() async {
    String selectedType = '혈당';
    final TextEditingController valueController = TextEditingController();

    final HealthRecord? result = await showDialog<HealthRecord>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('건강 기록 추가'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: '항목', border: OutlineInputBorder()),
                    items: const <String>['혈당', '혈압', '체중', '체온', '산소포화도', '증상']
                        .map((String value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (String? value) {
                      setLocalState(() => selectedType = value ?? selectedType);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueController,
                    decoration: const InputDecoration(labelText: '측정값 또는 내용', border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
                FilledButton(
                  onPressed: () {
                    if (valueController.text.trim().isEmpty) return;
                    Navigator.pop(dialogContext, HealthRecord(selectedType, valueController.text.trim(), DateTime.now()));
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() => records.insert(0, result));
    }
  }

  Future<void> _addSchedule() async {
    String selectedCategory = '병원';
    final TextEditingController titleController = TextEditingController();
    final TextEditingController memoController = TextEditingController();

    final HealthSchedule? result = await showDialog<HealthSchedule>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocalState) {
            return AlertDialog(
              title: const Text('건강 일정 추가'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: '종류', border: OutlineInputBorder()),
                      items: const <String>['병원', '복약', '검사', '기타']
                          .map((String value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                          .toList(),
                      onChanged: (String? value) {
                        setLocalState(() => selectedCategory = value ?? selectedCategory);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: titleController, decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(controller: memoController, decoration: const InputDecoration(labelText: '날짜·시간·메모', border: OutlineInputBorder())),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) return;
                    Navigator.pop(dialogContext, HealthSchedule(selectedCategory, titleController.text.trim(), memoController.text.trim()));
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() => schedules.insert(0, result));
    }
  }

  String _formatTime(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}
