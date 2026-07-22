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
      profile = HealthProfile.fromJson(rawProfile);
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
