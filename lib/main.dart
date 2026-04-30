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
        sendPort?.send('SEND_SMS_ACTION');
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

  final Telephony telephony = Telephony.instance;
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
  }

  void _bindReceivePort() async {
    ReceivePort? port = await FlutterForegroundTask.receivePort;
    if (port != null) {
      _receivePort = port;
      _receivePort?.listen((msg) {
        if (msg == 'SEND_SMS_ACTION') {
          _executeEmergencySms();
        }
      });
    } else {
      Future.delayed(const Duration(seconds: 1), _bindReceivePort);
    }
  }

  Future<void> _executeEmergencySms() async {
    final p = await SharedPreferences.getInstance();
    List contacts = json.decode(p.getString('contacts_list') ?? "[]");

    if (contacts.isEmpty) return;

    String locationStr = "좌표 없음";

    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );

      locationStr =
          "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {}

    for (var c in contacts) {
      String num = c['number'].replaceAll(RegExp(r'[^0-9]'), '');

      await telephony.sendSms(
        to: num,
        message: "[안심 지키미] 응답 없음\n위치: $locationStr",
      );
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety',
        channelName: '안심지키미',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 30000,
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "홈"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "기록"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "설정"),
        ],
      ),
    );
  }
}

/* =========================
   HOME (UI 유지)
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

  void loadLogs() {}

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
            if (await FlutterContacts.requestPermission()) {
              final c = await FlutterContacts.openExternalPicker();
              if (c != null && c.phones.isNotEmpty) {
                setState(() {
                  _contacts.add({
                    'name': c.displayName,
                    'number': c.phones.first.number,
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
