import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class GeminiAttachment {
  const GeminiAttachment({required this.bytes, required this.mimeType, required this.name});
  final List<int> bytes;
  final String mimeType;
  final String name;
}

class GeminiResult {
  GeminiResult({
    required this.answer,
    required this.followUpQuestion,
    required this.records,
    required this.profileUpdate,
    required this.calendarSuggestions,
  });

  final String answer;
  final String followUpQuestion;
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> profileUpdate;
  final List<CalendarSuggestion> calendarSuggestions;
}

class GeminiService {
  static const _model = 'gemini-2.5-flash';
  static final _uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
  );

  Future<http.Response> _postWithRetry({
    required String apiKey,
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 75),
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .post(
              _uri,
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if (response.statusCode == 429 || response.statusCode >= 500) {
          lastError = Exception('Gemini HTTP ${response.statusCode}');
        } else {
          return response;
        }
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt < 2) await Future<void>.delayed(Duration(seconds: attempt + 1));
    }
    throw Exception('Gemini 연결 실패: $lastError');
  }

  Future<void> testConnection(String apiKey) async {
    final response = await _postWithRetry(
      apiKey: apiKey,
      timeout: const Duration(seconds: 20),
      body: {
        'contents': [
          {
            'parts': [
              {'text': 'Reply only with OK'}
            ]
          }
        ]
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Gemini HTTP ${response.statusCode}');
    }
  }

  String _simpleName(dynamic value) {
    if (value is Map) {
      for (final key in const ['name', 'condition', 'disease', 'title', 'medicine']) {
        final text = value[key]?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      return '';
    }
    final text = value?.toString().trim() ?? '';
    if (text.startsWith('{') && text.contains('name:')) {
      final match = RegExp(r'name:\s*([^,}]+)').firstMatch(text);
      return match?.group(1)?.trim() ?? '';
    }
    return text;
  }

  List<String> _simpleList(dynamic value, {int maxItems = 12}) {
    if (value is! List) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      final name = _simpleName(item);
      final key = RecordDeduplicator.normalize(name);
      if (name.isNotEmpty && seen.add(key)) result.add(name);
      if (result.length >= maxItems) break;
    }
    return result;
  }

  Map<String, List<String>> _simpleGrouped(dynamic value, {int maxItems = 12}) {
    if (value is! Map) return const {};
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final department = entry.key.toString().trim();
      final items = _simpleList(entry.value, maxItems: maxItems);
      if (department.isNotEmpty && items.isNotEmpty) result[department] = items;
    }
    return result;
  }

  Map<String, dynamic> _sanitizeProfile(Map<String, dynamic> raw) {
    return {
      'confirmedConditions': _simpleList(raw['confirmedConditions'], maxItems: 8),
      'inferredConditions': _simpleList(raw['inferredConditions'], maxItems: 8),
      'medications': _simpleList(raw['medications'], maxItems: 30),
      'medicationsByDepartment': _simpleGrouped(raw['medicationsByDepartment'], maxItems: 20),
      'inferredConditionsByDepartment': _simpleGrouped(raw['inferredConditionsByDepartment'], maxItems: 8),
      'allergies': _simpleList(raw['allergies'], maxItems: 8),
      'notes': _simpleList(raw['notes'], maxItems: 8),
    };
  }

  Future<GeminiResult> analyze({
    required String apiKey,
    required String userText,
    required List<GeminiAttachment> attachments,
    required HealthProfile profile,
    required String responseLanguage,
  }) async {
    final prompt = '''
You are a safety-focused personal health assistant. Respond in $responseLanguage.
Analyze the user text and all attached prescriptions, images, PDFs and documents together.

Stored health profile:
${jsonEncode(profile.toJson())}

Display and storage rules:
- Keep the user-facing summary short and easy to scan.
- Organize prescription medicines by medical department.
- In the health-status view, group medicine-based possibilities by common disease name, for example 당뇨, 고혈압, 고지혈증, 알레르기, 위장질환, 혈액순환질환, 신경질환, 안과질환.
- Do not create one disease card for every medicine.
- Merge duplicate or closely related disease names into one plain disease label.
- Return condition and medication arrays as plain strings only. Never put maps/objects such as {name: ..., source: ...} inside profile arrays.
- Keep medicine names and detailed dosage inside department prescription records, not in the health-status disease list.
- Limit inferredConditions to the most relevant 8 grouped disease names.
- A medicine-based disease is only an estimate. Never present it as a confirmed diagnosis.
- If a diagnosis is explicitly printed and readable, it may be confirmed; otherwise inferred only.

Prescription rules:
- Identify department, hospital, physician and prescription date when readable.
- Never invent a department. Use "진료과 확인 필요" when uncertain.
- Group all medicines from one prescription into one medication record.
- details may contain department, hospital, doctor, prescriptionDate and a medications list.
- Add medicine names as plain strings to medications and medicationsByDepartment.
- Add only grouped disease labels as plain strings to inferredConditions and inferredConditionsByDepartment.

Medication safety:
- Compare new medicines with stored medicines.
- Warn about exact duplicates, same ingredient, same drug class or overlapping prescriptions.
- Begin the answer with "⚠️ 중복 처방 가능성" when relevant.
- Tell the user to confirm with a doctor or pharmacist and not to change medicines independently.

Return exactly one JSON object without markdown fences:
{
  "answer":"brief readable summary",
  "followUpQuestion":"one important question or empty",
  "records":[{
    "category":"medication|condition|hospital|schedule|lab|vital|diet|symptom|document|activity|other",
    "title":"내과 처방전",
    "summary":"short summary",
    "details":{"department":"내과","hospital":"","doctor":"","prescriptionDate":"","medications":[]},
    "confidence":0.0
  }],
  "profileUpdate":{
    "confirmedConditions":["당뇨"],
    "inferredConditions":["고혈압","고지혈증"],
    "medications":["약 이름"],
    "medicationsByDepartment":{"내과":["약 이름"]},
    "inferredConditionsByDepartment":{"내과":["고혈압","고지혈증"]},
    "allergies":[],
    "notes":[]
  },
  "calendarSuggestions":[]
}
User input: $userText
''';

    final parts = <Map<String, dynamic>>[
      {'text': prompt}
    ];
    for (final attachment in attachments) {
      parts.add({
        'inline_data': {
          'mime_type': attachment.mimeType,
          'data': base64Encode(attachment.bytes),
        }
      });
    }

    final response = await _postWithRetry(
      apiKey: apiKey,
      body: {
        'contents': [
          {'parts': parts}
        ],
        'generationConfig': {'temperature': 0.1, 'responseMimeType': 'application/json'},
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.length > 400 ? response.body.substring(0, 400) : response.body;
      throw Exception('Gemini HTTP ${response.statusCode}: $body');
    }

    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = envelope['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) throw const FormatException('Gemini 응답 후보가 없습니다.');
    final first = Map<String, dynamic>.from(candidates.first as Map);
    final content = Map<String, dynamic>.from((first['content'] as Map?) ?? const {});
    final responseParts = content['parts'] as List<dynamic>?;
    if (responseParts == null || responseParts.isEmpty) throw const FormatException('Gemini 응답 내용이 없습니다.');
    var raw = Map<String, dynamic>.from(responseParts.first as Map)['text']?.toString().trim() ?? '';
    raw = raw.replaceFirst(RegExp(r'^```(?:json)?\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    final rawProfile = Map<String, dynamic>.from((parsed['profileUpdate'] as Map?) ?? const {});

    return GeminiResult(
      answer: parsed['answer']?.toString().trim() ?? '분석을 완료했습니다.',
      followUpQuestion: parsed['followUpQuestion']?.toString().trim() ?? '',
      records: (parsed['records'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      profileUpdate: _sanitizeProfile(rawProfile),
      calendarSuggestions: (parsed['calendarSuggestions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => CalendarSuggestion.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
