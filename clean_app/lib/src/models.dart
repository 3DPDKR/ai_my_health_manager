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

class HealthProfile {
  const HealthProfile({
    this.confirmedConditions = const [],
    this.inferredConditions = const [],
    this.medications = const [],
    this.allergies = const [],
    this.notes = const [],
  });

  final List<String> confirmedConditions;
  final List<String> inferredConditions;
  final List<String> medications;
  final List<String> allergies;
  final List<String> notes;

  bool get isSparse =>
      confirmedConditions.isEmpty &&
      inferredConditions.isEmpty &&
      medications.isEmpty &&
      allergies.isEmpty &&
      notes.isEmpty;

  Map<String, dynamic> toJson() => {
        'confirmedConditions': confirmedConditions,
        'inferredConditions': inferredConditions,
        'medications': medications,
        'allergies': allergies,
        'notes': notes,
      };

  factory HealthProfile.fromJson(Map<String, dynamic> json) => HealthProfile(
        confirmedConditions: List<String>.from(json['confirmedConditions'] ?? const []),
        inferredConditions: List<String>.from(json['inferredConditions'] ?? const []),
        medications: List<String>.from(json['medications'] ?? const []),
        allergies: List<String>.from(json['allergies'] ?? const []),
        notes: List<String>.from(json['notes'] ?? const []),
      );

  HealthProfile merged(Map<String, dynamic> update) {
    List<String> merge(List<String> current, dynamic incoming) {
      final values = incoming is List ? incoming.map((e) => e.toString().trim()) : const <String>[];
      return {...current, ...values.where((e) => e.isNotEmpty)}.toList();
    }

    return HealthProfile(
      confirmedConditions: merge(confirmedConditions, update['confirmedConditions']),
      inferredConditions: merge(inferredConditions, update['inferredConditions']),
      medications: merge(medications, update['medications']),
      allergies: merge(allergies, update['allergies']),
      notes: merge(notes, update['notes']),
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
