import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class AppPreferences {
  static const _onboardingKey = 'onboarding_completed_v1';
  static const _notificationKey = 'notifications_enabled_v1';
  static const _backgroundKey = 'background_enabled_v1';

  Future<bool> get onboardingCompleted async =>
      (await SharedPreferences.getInstance()).getBool(_onboardingKey) ?? false;

  Future<void> setOnboardingCompleted(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_onboardingKey, value);

  Future<bool> get notificationsEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_notificationKey) ?? true;

  Future<void> setNotificationsEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_notificationKey, value);

  Future<bool> get backgroundEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_backgroundKey) ?? true;

  Future<void> setBackgroundEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_backgroundKey, value);
}

class PermissionSnapshot {
  const PermissionSnapshot({
    required this.camera,
    required this.photos,
    required this.microphone,
    required this.notification,
    required this.calendar,
  });

  final PermissionStatus camera;
  final PermissionStatus photos;
  final PermissionStatus microphone;
  final PermissionStatus notification;
  final PermissionStatus calendar;

  bool get essentialGranted => camera.isGranted && microphone.isGranted;
}

class PermissionService {
  Future<PermissionSnapshot> inspect() async => PermissionSnapshot(
        camera: await Permission.camera.status,
        photos: await Permission.photos.status,
        microphone: await Permission.microphone.status,
        notification: await Permission.notification.status,
        calendar: await Permission.calendarFullAccess.status,
      );

  Future<PermissionSnapshot> requestEssential() async {
    await [
      Permission.camera,
      Permission.photos,
      Permission.microphone,
      Permission.notification,
      Permission.calendarFullAccess,
    ].request();
    return inspect();
  }

  Future<bool> openSettings() => openAppSettings();
}

class SpeechService {
  final SpeechToText _speech = SpeechToText();

  bool get isListening => _speech.isListening;

  Future<bool> start({required void Function(String text) onText}) async {
    final available = await _speech.initialize();
    if (!available) return false;
    await _speech.listen(
      localeId: 'ko_KR',
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (result) => onText(result.recognizedWords),
    );
    return true;
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() => _speech.cancel();
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    _initialized = true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'health_reminders',
          '건강 알림',
          channelDescription: '복약 및 병원 일정 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  Future<void> showTest() async {
    await initialize();
    await _plugin.show(
      id: 9000,
      title: 'AI 건강비서',
      body: '알림이 정상적으로 작동합니다.',
      notificationDetails: _details,
    );
  }

  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await initialize();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(int id) async => _plugin.cancel(id: id);
  Future<void> cancelAll() async => _plugin.cancelAll();
}
