import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

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

  Future<void> testConnection(String apiKey) async {
    final response = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': 'Reply only with OK'}
                ]
              }
            ]
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Gemini HTTP ${response.statusCode}');
    }
  }

  Future<GeminiResult> analyze({
    required String apiKey,
    required String userText,
    required List<List<int>> images,
    required HealthProfile profile,
    required String responseLanguage,
  }) async {
    final prompt = '''
You are an AI-first personal health assistant.
Respond in $responseLanguage.
The user wants a useful natural answer first. Never show raw JSON, markdown code fences, database field names, or internal categories.

Analyze chat and all attached images together. Images may be prescriptions, medication bags, hospital records, lab results, discharge papers, diet photos, or glucose/blood-pressure displays.

Stored health profile:
${jsonEncode(profile.toJson())}

Required behavior:
1. Give a clear natural-language answer first.
2. Extract and structure prescriptions, medications, hospital records, laboratory values, diet, symptoms, and vital signs.
3. Infer possible diseases from medications only as inferred conditions. Never present them as confirmed diagnoses.
4. Ask the user to confirm inferred conditions.
5. If the health profile is insufficient for safe diet or health recommendations, ask only the most important missing question.
6. For food, compare the meal with confirmed/inferred conditions, medications, allergies, and known lab values. Suggest practical alternatives.
7. Calculate medication end dates or likely follow-up dates only when prescription date and duration are readable. Mark estimates clearly.
8. Suggest Google Calendar events for medication end dates, follow-up visits, tests, or confirmed hospital appointments.
9. Preserve distinctions between confirmed information, inferred information, and information needing confirmation.
10. Return exactly one JSON object using this schema:
{
  "answer":"natural-language answer only",
  "followUpQuestion":"one important question if needed, otherwise empty",
  "records":[
    {
      "category":"medication|condition|hospital|schedule|lab|vital|diet|symptom|document|activity|other",
      "title":"user-friendly title",
      "summary":"short summary",
      "details":{"label":"value"},
      "confidence":0.0
    }
  ],
  "profileUpdate":{
    "confirmedConditions":[],
    "inferredConditions":[],
    "medications":[],
    "allergies":[],
    "notes":[]
  },
  "calendarSuggestions":[
    {
      "title":"event title",
      "start":"ISO-8601 local datetime",
      "end":"ISO-8601 local datetime",
      "description":"reason and source"
    }
  ]
}
Do not wrap the JSON in markdown fences.
User input: $userText
''';

    final parts = <Map<String, dynamic>>[
      {'text': prompt}
    ];
    for (final bytes in images) {
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(bytes),
        }
      });
    }

    final response = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'contents': [
              {'parts': parts}
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 75));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.length > 400 ? response.body.substring(0, 400) : response.body;
      throw Exception('Gemini HTTP ${response.statusCode}: $body');
    }

    final envelope = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = envelope['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const FormatException('Gemini 응답 후보가 없습니다.');
    }

    final first = Map<String, dynamic>.from(candidates.first as Map);
    final content = Map<String, dynamic>.from((first['content'] as Map?) ?? const {});
    final responseParts = content['parts'] as List<dynamic>?;
    if (responseParts == null || responseParts.isEmpty) {
      throw const FormatException('Gemini 응답 내용이 없습니다.');
    }

    final firstPart = Map<String, dynamic>.from(responseParts.first as Map);
    final raw = firstPart['text']?.toString() ?? '';
    if (raw.isEmpty) throw const FormatException('Gemini 응답이 비어 있습니다.');

    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    final recordList = (parsed['records'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final profileUpdate = Map<String, dynamic>.from((parsed['profileUpdate'] as Map?) ?? const {});
    final calendars = (parsed['calendarSuggestions'] as List<dynamic>? ?? const [])
        .map((e) => CalendarSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return GeminiResult(
      answer: parsed['answer']?.toString().trim() ?? '분석을 완료했습니다.',
      followUpQuestion: parsed['followUpQuestion']?.toString().trim() ?? '',
      records: recordList,
      profileUpdate: profileUpdate,
      calendarSuggestions: calendars,
    );
  }
}
