import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StoredHealthState {
  StoredHealthState({
    required this.records,
    required this.profile,
    required this.logs,
  });

  final List<HealthRecord> records;
  final HealthProfile profile;
  final List<ErrorLogEntry> logs;
}

class StorageService {
  static const _recordsKey = 'health_records_v3';
  static const _profileKey = 'health_profile_v3';
  static const _logsKey = 'error_logs_v3';

  String _plainName(dynamic value) {
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

  List<String> _plainList(dynamic value, {int maxItems = 30}) {
    if (value is! List) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      final name = _plainName(item);
      final key = RecordDeduplicator.normalize(name);
      if (name.isNotEmpty && seen.add(key)) result.add(name);
      if (result.length >= maxItems) break;
    }
    return result;
  }

  Map<String, List<String>> _plainGrouped(dynamic value, {int maxItems = 20}) {
    if (value is! Map) return const {};
    final result = <String, List<String>>{};
    for (final entry in value.entries) {
      final department = entry.key.toString().trim();
      final items = _plainList(entry.value, maxItems: maxItems);
      if (department.isNotEmpty && items.isNotEmpty) result[department] = items;
    }
    return result;
  }

  Map<String, dynamic> _migrateProfile(Map<String, dynamic> raw) {
    return {
      'confirmedConditions': _plainList(raw['confirmedConditions'], maxItems: 12),
      'inferredConditions': _plainList(raw['inferredConditions'], maxItems: 8),
      'medications': _plainList(raw['medications'], maxItems: 40),
      'medicationsByDepartment': _plainGrouped(raw['medicationsByDepartment']),
      'inferredConditionsByDepartment': _plainGrouped(raw['inferredConditionsByDepartment'], maxItems: 8),
      'allergies': _plainList(raw['allergies'], maxItems: 10),
      'notes': _plainList(raw['notes'], maxItems: 12),
    };
  }

  Future<StoredHealthState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final records = <HealthRecord>[];
    final logs = <ErrorLogEntry>[];
    var profile = const HealthProfile();

    try {
      final rawRecords = jsonDecode(prefs.getString(_recordsKey) ?? '[]') as List<dynamic>;
      records.addAll(rawRecords.map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (_) {}

    try {
      final rawProfile = jsonDecode(prefs.getString(_profileKey) ?? '{}') as Map<String, dynamic>;
      final migrated = _migrateProfile(rawProfile);
      profile = HealthProfile.fromJson(migrated);
      await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    } catch (_) {}

    try {
      final rawLogs = jsonDecode(prefs.getString(_logsKey) ?? '[]') as List<dynamic>;
      logs.addAll(rawLogs.map((e) => ErrorLogEntry.fromJson(Map<String, dynamic>.from(e as Map))));
    } catch (_) {}

    return StoredHealthState(records: records, profile: profile, logs: logs);
  }

  Future<void> save({
    required List<HealthRecord> records,
    required HealthProfile profile,
    required List<ErrorLogEntry> logs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, jsonEncode(records.map((e) => e.toJson()).toList()));
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    await prefs.setString(_logsKey, jsonEncode(logs.take(100).map((e) => e.toJson()).toList()));
  }
}
