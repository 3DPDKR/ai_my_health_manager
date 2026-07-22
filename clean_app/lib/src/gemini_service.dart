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

  Future<GeminiResult> analyze({
    required String apiKey,
    required String userText,
    required List<GeminiAttachment> attachments,
    required HealthProfile profile,
    required String responseLanguage,
  }) async {
    final prompt = '''
You are a safety-focused personal health assistant. Respond in $responseLanguage.
Analyze the user text and every attached image, prescription, PDF, and document together.

Stored health profile:
${jsonEncode(profile.toJson())}

Prescription organization rules:
- Identify the medical department from the document, hospital name, physician name, medicine indications, and context.
- Use a visible department such as 내과, 신경과, 안과, 정형외과, 피부과, 이비인후과, 비뇨의학과, 정신건강의학과, or 기타/확인 필요.
- Never invent a department. When uncertain, use "진료과 확인 필요".
- Group medicines from the same prescription into one medication record per department and prescription date.
- In every prescription medication record, details must contain:
  department, hospital, doctor, prescriptionDate, medications, relatedConditions, inferenceBasis.
- medications must preserve each readable medicine name, active ingredient if known, dose, frequency, timing, duration, and purpose.
- relatedConditions are medication-based possibilities only. Store them as inferred, never confirmed.
- For each inferred condition, include a brief reason such as which medicine or drug class led to the inference.
- If the prescription explicitly prints a diagnosis, it may be stored as confirmed only when clearly readable. Otherwise keep it inferred.
- Add all medicines to profileUpdate.medications and also group them in profileUpdate.medicationsByDepartment.
- Add medication-based disease possibilities to profileUpdate.inferredConditions and also group them in profileUpdate.inferredConditionsByDepartment.
- Do not duplicate the same medicine or condition within a department.

Critical medication safety rules:
- Compare every newly extracted medication with all stored medications.
- Detect exact duplicates, same active ingredient with different brand names, same drug class duplication, overlapping prescription periods, and likely replacement prescriptions.
- If duplicate medication or duplicate prescription is possible, begin answer with "⚠️ 중복 처방 가능성" in Korean, or equivalent in the response language.
- Name the compared medicines and tell the user not to stop, combine, or change medicines independently and to confirm with a doctor or pharmacist.
- Distinguish confirmed duplication from possible duplication when ingredient data is incomplete.
- Keep the duplicate warning visible in the natural answer.

Other rules:
1. Give a concise natural-language summary organized by medical department.
2. Extract hospital records, laboratory values, diet, symptoms, vital signs, and schedules when present.
3. Never present medication-based disease inference as a diagnosis.
4. Avoid duplicate records and repeated medicines.
5. Suggest calendar events only when a reliable date and time exist.
6. Return exactly one JSON object without markdown fences:
{
  "answer":"natural answer organized by medical department and including safety warnings",
  "followUpQuestion":"one important question or empty",
  "records":[
    {
      "category":"medication|condition|hospital|schedule|lab|vital|diet|symptom|document|activity|other",
      "title":"example: 내과 처방전",
      "summary":"short department-based summary",
      "details":{
        "department":"내과",
        "hospital":"hospital name or empty",
        "doctor":"doctor name or empty",
        "prescriptionDate":"YYYY-MM-DD or empty",
        "medications":[{"name":"","ingredient":"","dose":"","frequency":"","timing":"","duration":"","purpose":""}],
        "relatedConditions":["possible condition"],
        "inferenceBasis":["medicine or ingredient -> possible condition"]
      },
      "confidence":0.0
    }
  ],
  "profileUpdate":{
    "confirmedConditions":[],
    "inferredConditions":[],
    "medications":[],
    "medicationsByDepartment":{"내과":[]},
    "inferredConditionsByDepartment":{"내과":[]},
    "allergies":[],
    "notes":[]
  },
  "calendarSuggestions":[{"title":"title","start":"ISO-8601 local datetime","end":"ISO-8601 local datetime","description":"reason"}]
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
        'generationConfig': {'temperature': 0.15, 'responseMimeType': 'application/json'},
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

    return GeminiResult(
      answer: parsed['answer']?.toString().trim() ?? '분석을 완료했습니다.',
      followUpQuestion: parsed['followUpQuestion']?.toString().trim() ?? '',
      records: (parsed['records'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      profileUpdate: Map<String, dynamic>.from((parsed['profileUpdate'] as Map?) ?? const {}),
      calendarSuggestions: (parsed['calendarSuggestions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => CalendarSuggestion.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
