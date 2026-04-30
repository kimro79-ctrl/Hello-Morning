import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:telephony/telephony.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

/* =========================
   BACKGROUND TASK
========================= */
class FirstTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();

    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');

    if (last == null || contactsJson == null || contactsJson == "[]") return;

    try {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
      int selectedHours = p.getInt('selectedHours') ?? 1;
      int limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

      double diffSeconds = DateTime.now().difference(lastTime).inSeconds.toDouble();
      double limitSeconds = (limitMin * 60) - 30;

      if (diffSeconds >= limitSeconds) {
        String? lastSent = p.getString('lastEmergencySent');

        if (lastSent != null) {
          DateTime lastSentTime = DateTime.parse(lastSent);
          if (DateTime.now().difference(lastSentTime).inSeconds >= 270) {
            sendPort?.send('SEND_SMS_ACTION');
          }
        } else {
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
   APP ROOT
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
      ),
      home: const MainNavigation(),
    );
  }
}

/* =========================
   MAIN NAVIGATION
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

  final Telephony telephony = Telephony.instance;

  @override
  void initState() {
    super.initState();

    _screens = [
      const HomeScreen(),
      HistoryScreen(key: _historyKey),
      const SettingScreen()
    ];

    _initForegroundTask();
    _bindReceivePort();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
    });
  }

  void _bindReceivePort() async {
    ReceivePort? port = await FlutterForegroundTask.receivePort;
    if (port != null) {
      _initReceivePort(port);
    } else {
      Future.delayed(const Duration(seconds: 1), _bindReceivePort);
    }
  }

  void _initReceivePort(ReceivePort port) {
    _receivePort?.close();
    _receivePort = port;

    _receivePort?.listen((message) {
      if (message == 'SEND_SMS_ACTION') {
        _executeEmergencySms();
      }
    });
  }

  Future<void> _executeEmergencySms() async {
    final p = await SharedPreferences.getInstance();

    List contacts = json.decode(p.getString('contacts_list') ?? "[]");
    if (contacts.isEmpty) return;

    String locationStr = "좌표 없음";

    try {
      Position pos = await Geolocator.getCurrentPosition();
      locationStr =
          "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {}

    List history = json.decode(p.getString('history_logs') ?? "[]");

    for (var c in contacts) {
      try {
        String number = c['number'].replaceAll(RegExp(r'[^0-9]'), '');

        await telephony.sendSms(
          to: number,
          message:
              "[안심 지키미]\n응답 없음 감지\n위치: $locationStr\n확인 부탁드립니다.",
        );

        history.insert(0, {
          'type': '비상 알림',
          'time': DateFormat('MM/dd HH:mm').format(DateTime.now()),
          'msg': '${c['name']}에게 전송 완료'
        });
      } catch (_) {
        history.insert(0, {
          'type': '에러',
          'time': DateFormat('MM/dd HH:mm').format(DateTime.now()),
          'msg': '전송 실패'
        });
      }
    }

    await p.setString('history_logs', json.encode(history.take(30).toList()));
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());

    _historyKey.currentState?.loadLogs();
  }

  Future<void> _initialSetup() async {
    await [
      Permission.sms,
      Permission.location,
      Permission.locationAlways,
      Permission.contacts
    ].request();

    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_channel',
        channelName: '안심 지키미',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 30000,
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            if (i == 1) _historyKey.currentState?.loadLogs();
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "홈"),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: "기록"),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: "설정"),
          ],
        ),
      ),
    );
  }
}
