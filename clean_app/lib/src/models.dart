import 'dart:convert';

class HealthRecord {
  HealthRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.details,
    required this.createdAt,
    required this.inputMethod,
    required this.confidence,
    this.sourceText = '',
  });

  final String id;
  final String category;
  final String title;
  final String summary;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  final String inputMethod;
  final double confidence;
  final String sourceText;

  static String _normalize(Object? value) => value
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[^가-힣a-z0-9]'), '');

  String get duplicateKey {
    final day = '${createdAt.year.toString().padLeft(4, '0')}'
        '${createdAt.month.toString().padLeft(2, '0')}'
        '${createdAt.day.toString().padLeft(2, '0')}';
    final ordered = details.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final detailText = ordered.map((e) => '${e.key}:${e.value}').join('|');
    return [category, title, summary, detailText, day].map(_normalize).join('::');
  }

  bool isDuplicateOf(HealthRecord other) => duplicateKey == other.duplicateKey;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'summary': summary,
        'details': details,
        'createdAt': createdAt.toIso8601String(),
        'inputMethod': inputMethod,
        'confidence': confidence,
        'sourceText': sourceText,
      };

  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        category: json['category']?.toString() ?? 'other',
        title: json['title']?.toString() ?? '건강 기록',
        summary: json['summary']?.toString() ?? '',
        details: Map<String, dynamic>.from((json['details'] as Map?) ?? const {}),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        inputMethod: json['inputMethod']?.toString() ?? 'chat',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        sourceText: json['sourceText']?.toString() ?? '',
      );
}

class RecordDeduplicator {
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[^가-힣a-z0-9]'), '');

  static List<HealthRecord> uniqueNewRecords({
    required List<HealthRecord> existing,
    required List<HealthRecord> incoming,
  }) {
    final keys = existing.map((e) => e.duplicateKey).toSet();
    final result = <HealthRecord>[];
    for (final record in incoming) {
      if (keys.add(record.duplicateKey)) result.add(record);
    }
    return result;
  }

  static bool sameDocumentBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    return base64Encode(first) == base64Encode(second);
  }
}

class HealthProfile {
  const HealthProfile({
    this.confirmedConditions = const [],
    this.inferredConditions = const [],
    this.medications = const [],
    this.medicationsByDepartment = const {},
    this.inferredConditionsByDepartment = const {},
    this.allergies = const [],
    this.notes = const [],
  });

  final List<String> confirmedConditions;
  final List<String> inferredConditions;
  final List<String> medications;
  final Map<String, List<String>> medicationsByDepartment;
  final Map<String, List<String>> inferredConditionsByDepartment;
  final List<String> allergies;
  final List<String> notes;

  bool get isSparse =>
      confirmedConditions.isEmpty &&
      inferredConditions.isEmpty &&
      medications.isEmpty &&
      medicationsByDepartment.isEmpty &&
      allergies.isEmpty &&
      notes.isEmpty;

  Map<String, dynamic> toJson() => {
        'confirmedConditions': confirmedConditions,
        'inferredConditions': inferredConditions,
        'medications': medications,
        'medicationsByDepartment': medicationsByDepartment,
        'inferredConditionsByDepartment': inferredConditionsByDepartment,
        'allergies': allergies,
        'notes': notes,
      };

  static Map<String, List<String>> _readGrouped(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final department = entry.key.toString().trim();
      if (department.isEmpty || entry.value is! List) continue;
      final items = (entry.value as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (items.isNotEmpty) result[department] = items;
    }
    return result;
  }

  factory HealthProfile.fromJson(Map<String, dynamic> json) => HealthProfile(
        confirmedConditions: List<String>.from(json['confirmedConditions'] ?? const []),
        inferredConditions: List<String>.from(json['inferredConditions'] ?? const []),
        medications: List<String>.from(json['medications'] ?? const []),
        medicationsByDepartment: _readGrouped(json['medicationsByDepartment']),
        inferredConditionsByDepartment: _readGrouped(json['inferredConditionsByDepartment']),
        allergies: List<String>.from(json['allergies'] ?? const []),
        notes: List<String>.from(json['notes'] ?? const []),
      );

  HealthProfile merged(Map<String, dynamic> update) {
    List<String> mergeList(List<String> current, dynamic incoming) {
      final output = <String>[];
      final seen = <String>{};
      for (final item in <String>[
        ...current,
        if (incoming is List) ...incoming.map((e) => e.toString().trim()),
      ]) {
        if (item.isEmpty) continue;
        final key = RecordDeduplicator.normalize(item);
        if (seen.add(key)) output.add(item);
      }
      return output;
    }

    Map<String, List<String>> mergeGrouped(
      Map<String, List<String>> current,
      dynamic incoming,
    ) {
      final result = <String, List<String>>{
        for (final entry in current.entries) entry.key: List<String>.from(entry.value),
      };
      final parsed = _readGrouped(incoming);
      for (final entry in parsed.entries) {
        final existingDepartment = result.keys.cast<String?>().firstWhere(
              (key) => RecordDeduplicator.normalize(key ?? '') == RecordDeduplicator.normalize(entry.key),
              orElse: () => null,
            );
        final department = existingDepartment ?? entry.key;
        result[department] = mergeList(result[department] ?? const [], entry.value);
      }
      return result;
    }

    final groupedMedications = mergeGrouped(
      medicationsByDepartment,
      update['medicationsByDepartment'],
    );
    final groupedInferred = mergeGrouped(
      inferredConditionsByDepartment,
      update['inferredConditionsByDepartment'],
    );
    final allGroupedMedications = groupedMedications.values.expand((e) => e).toList();
    final allGroupedConditions = groupedInferred.values.expand((e) => e).toList();

    return HealthProfile(
      confirmedConditions: mergeList(confirmedConditions, update['confirmedConditions']),
      inferredConditions: mergeList(
        mergeList(inferredConditions, update['inferredConditions']),
        allGroupedConditions,
      ),
      medications: mergeList(
        mergeList(medications, update['medications']),
        allGroupedMedications,
      ),
      medicationsByDepartment: groupedMedications,
      inferredConditionsByDepartment: groupedInferred,
      allergies: mergeList(allergies, update['allergies']),
      notes: mergeList(notes, update['notes']),
    );
  }
}

class CalendarSuggestion {
  CalendarSuggestion({
    required this.title,
    required this.start,
    required this.end,
    required this.description,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String description;

  String get duplicateKey =>
      '${RecordDeduplicator.normalize(title)}::${start.toLocal().toIso8601String().substring(0, 16)}';

  factory CalendarSuggestion.fromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse(json['start']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 1));
    final end = DateTime.tryParse(json['end']?.toString() ?? '') ?? start.add(const Duration(hours: 1));
    return CalendarSuggestion(
      title: json['title']?.toString() ?? '건강 일정',
      start: start,
      end: end,
      description: json['description']?.toString() ?? '',
    );
  }
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
  final List<List<int>> images;
}
