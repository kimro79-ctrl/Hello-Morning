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
      int diffSeconds = DateTime.now().difference(lastTime).inSeconds;
      int limitSeconds = (limitMin * 60) - 30; 

      if (diffSeconds >= limitSeconds) {
        String? lastSentStr = p.getString('lastEmergencySent');
        if (lastSentStr != null) {
          DateTime lastSentTime = DateTime.parse(lastSentStr);
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFF5F5DC),
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFFF8A65),
        ),
        home: const MainNavigation(),
      );
}

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
    _screens = [const HomeScreen(), HistoryScreen(key: _historyKey), const SettingScreen()];
    _initForegroundTask();
    _bindReceivePort();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
    });
  }

  void _bindReceivePort() async {
    ReceivePort? port = await FlutterForegroundTask.receivePort;
    if (port != null) {
      _receivePort?.close();
      _receivePort = port;
      _receivePort?.listen((message) {
        if (message == 'SEND_SMS_ACTION') _executeEmergencySms();
      });
    }
  }

  Future<void> _executeEmergencySms() async {
    final p = await SharedPreferences.getInstance();
    String? contactsJson = p.getString('contacts_list');
    List contacts = json.decode(contactsJson ?? "[]");
    if (contacts.isEmpty) return;

    String locationStr = "좌표 확인 불가";
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low, timeLimit: const Duration(seconds: 4));
      locationStr = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {}

    List history = json.decode(p.getString('history_logs') ?? "[]");
    for (var c in contacts) {
      if (c['number'] != null) {
        String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
        try {
          await BackgroundSms.sendMessage(phoneNumber: cleanNumber, message: "[안심지키미] 응답이 없어 연락드립니다.\n좌표: $locationStr\n구글맵에서 좌표확인 부탁합니다.");
          history.insert(0, {'type': '비상 알림', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '보호자(${c['name']})에게 문자 발송'});
        } catch (_) {}
      }
    }
    await p.setString('history_logs', json.encode(history.take(30).toList()));
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());
    _historyKey.currentState?.loadLogs();
  }

  Future<void> _initialSetup() async {
    await [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts, Permission.notification].request();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(channelId: 'safety_check', channelName: '안심 서비스', channelImportance: NotificationChannelImportance.MAX, priority: NotificationPriority.HIGH),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 30000, autoRunOnBoot: true, allowWakeLock: true),
    );
  }

  @override
  Widget build(BuildContext context) => WithForegroundTask(
        child: Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: const Color(0xFFFF8A65),
            onTap: (index) {
              setState(() => _currentIndex = index);
              if (index == 1) _historyKey.currentState?.loadLogs();
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
              BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
            ],
          ),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "오늘 하루 안부를 전해주세요"; 
  int _selectedHours = 1;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 하루 안부를 전해주세요"; 
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 50),
          const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [0, 1, 12, 24].map((h) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: ChoiceChip(
                label: Text(h == 0 ? "5분" : "$h시간"),
                selected: _selectedHours == h,
                onSelected: (v) async {
                  setState(() => _selectedHours = h);
                  (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                },
              ),
            )).toList(),
          ),
          const Spacer(),
          Text("마지막 체크인: $_lastCheckIn", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) async {
              setState(() => _isPressed = false);
              String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
              final p = await SharedPreferences.getInstance();
              await p.setString('lastCheckIn', now);
              await p.remove('lastEmergencySent');
              List history = json.decode(p.getString('history_logs') ?? "[]");
              history.insert(0, {'type': '활동 체크', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 안부 확인 완료'});
              await p.setString('history_logs', json.encode(history.take(30).toList()));
              setState(() => _lastCheckIn = now);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: _isPressed ? [] : [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(5, 5))],
                border: Border.all(color: const Color(0xFFFFD1DC), width: 5),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/smile.png',
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const Icon(Icons.face, size: 100, color: Colors.orange),
                ),
              ),
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List _logs = [];
  Future<void> loadLogs() async {
    final p = await SharedPreferences.getInstance();
    setState(() { _logs = json.decode(p.getString('history_logs') ?? "[]"); });
  }
  @override
  void initState() { super.initState(); loadLogs(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("기록")),
    body: ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, i) => ListTile(
        title: Text(_logs[i]['type']),
        subtitle: Text(_logs[i]['msg']),
        trailing: Text(_logs[i]['time']),
      ),
    ),
  );
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  List _contacts = [];
  bool _autoOn = false;
  @override
  void initState() { super.initState(); _load(); }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");
      _autoOn = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("설정")),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text("실시간 감시 모드"),
          value: _autoOn,
          onChanged: (v) async {
            final p = await SharedPreferences.getInstance();
            await p.setBool('auto_sms_enabled', v);
            setState(() => _autoOn = v);
            if (v) {
              await FlutterForegroundTask.startService(notificationTitle: "실행 중", notificationText: "보호 중입니다.", callback: startCallback);
            } else {
              await FlutterForegroundTask.stopService();
            }
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            ),
          ),
        ),
        ElevatedButton(onPressed: () async {
          final c = await ContactsService.openDeviceContactPicker();
          if (c != null) {
            setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
            (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
          }
        }, child: const Text("보호자 추가"))
      ],
    ),
  );
}
