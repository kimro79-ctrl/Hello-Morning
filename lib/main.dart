import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

/* =========================
   FOREGROUND CALLBACK
========================= */

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();

    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    final last = p.getString('lastCheckIn');
    final contactsJson = p.getString('contacts_list');

    if (last == null || contactsJson == null || contactsJson.isEmpty) return;

    try {
      final lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);

      final selectedHours = p.getInt('selectedHours') ?? 1;
      final limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

      final diffSeconds = DateTime.now().difference(lastTime).inSeconds;
      final limitSeconds = (limitMin * 60) - 30;

      if (diffSeconds >= limitSeconds) {
        final lastSentStr = p.getString('lastEmergencySent');

        if (lastSentStr == null ||
            DateTime.now()
                    .difference(DateTime.parse(lastSentStr))
                    .inSeconds >=
                270) {
          sendPort?.send('SEND_SMS_ACTION');
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

/* =========================
   MAIN
========================= */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailySafetyApp());
}

/* =========================
   APP
========================= */

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF5F5DC),
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFFF8A65),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 12),
          bodyMedium: TextStyle(fontSize: 11),
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

/* =========================
   NAVIGATION
========================= */

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey();

  late List<Widget> _screens;
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();

    _screens = [
      const HomeScreen(),
      HistoryScreen(key: _historyKey),
      const SettingScreen(),
    ];

    _initForegroundTask();
    _bindReceivePort();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
      _showGuideDialog();
    });
  }

  void _bindReceivePort() async {
    final port = await FlutterForegroundTask.receivePort;

    if (port != null) {
      _receivePort?.close();
      _receivePort = port;

      _receivePort!.listen((message) {
        if (message == 'SEND_SMS_ACTION') {
          _executeEmergencySms();
        }
      });
    } else {
      Future.delayed(const Duration(seconds: 1), _bindReceivePort);
    }
  }

  Future<void> _executeEmergencySms() async {
    final p = await SharedPreferences.getInstance();

    final contactsJson = p.getString('contacts_list');
    final List contacts = json.decode(contactsJson ?? "[]");

    if (contacts.isEmpty) return;

    String locationStr = "좌표 확인 불가";

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );

      locationStr =
          "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {}

    final List history =
        json.decode(p.getString('history_logs') ?? "[]");

    for (final c in contacts) {
      final raw = (c['number'] ?? '').toString();
      if (raw.isEmpty) continue;

      final clean = raw.replaceAll(RegExp(r'[^0-9]'), '');

      try {
        await BackgroundSms.sendMessage(
          phoneNumber: clean,
          message:
              "[1인가구 안심 지키미] 응답 없음\n좌표: $locationStr",
        );

        history.insert(0, {
          'type': '비상 알림',
          'time': DateFormat('MM/dd HH:mm').format(DateTime.now()),
          'msg': '보호자(${c['name']}) 발송 완료',
        });
      } catch (_) {
        history.insert(0, {
          'type': '에러',
          'time': DateFormat('MM/dd HH:mm').format(DateTime.now()),
          'msg': 'SMS 실패',
        });
      }
    }

    await p.setString('history_logs', json.encode(history.take(30).toList()));
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());

    _historyKey.currentState?.loadLogs();
    if (mounted) setState(() {});
  }

  Future<void> _initialSetup() async {
    await [
      Permission.sms,
      Permission.location,
      Permission.locationAlways,
      Permission.contacts,
      Permission.notification,
    ].request();

    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_v38',
        channelName: '1인가구 안심 지키미',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 30000,
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("안심 지키미 안내"),
        content: const Text("권한 설정 후 정상 동작합니다."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
          ],
        ),
      ),
    );
  }
}

/* =========================
   HOME (UI 그대로 유지)
========================= */

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "안부를 전해주세요";

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(_lastCheckIn));
  }
}

/* =========================
   HISTORY
========================= */

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List _logs = [];

  Future<void> loadLogs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _logs = json.decode(p.getString('history_logs') ?? "[]");
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("기록"));
  }
}

/* =========================
   SETTING
========================= */

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  List _contacts = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            if (await Permission.contacts.request().isGranted) {
              final c = await ContactsService.openDeviceContactPicker();

              if (c != null && c.phones != null && c.phones!.isNotEmpty) {
                setState(() {
                  _contacts.add({
                    'name': c.displayName ?? '',
                    'number': c.phones!.first.value ?? '',
                  });
                });

                final p = await SharedPreferences.getInstance();
                await p.setString('contacts_list', json.encode(_contacts));
              }
            }
          },
          child: const Text("연락처 추가"),
        ),
      ),
    );
  }
}
