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
      double diffSeconds = DateTime.now().difference(lastTime).inSeconds.toDouble();
      double limitSeconds = (limitMin * 60) - 30; 

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
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 13), 
            bodyMedium: TextStyle(fontSize: 12),
          ),
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
      _showDetailedGuide(); 
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

  void _initReceivePort(ReceivePort? port) {
    _receivePort?.close();
    _receivePort = port;
    _receivePort?.listen((message) {
      if (message == 'SEND_SMS_ACTION') _executeEmergencySms();
    });
  }

  Future<void> _executeEmergencySms() async {
    final p = await SharedPreferences.getInstance();
    String? contactsJson = p.getString('contacts_list');
    List contacts = json.decode(contactsJson ?? "[]");
    if (contacts.isEmpty) return;

    String locationStr = "좌표 확인 불가";
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 5));
      locationStr = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {
      Position? lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) locationStr = "${lastPos.latitude.toStringAsFixed(6)}, ${lastPos.longitude.toStringAsFixed(6)} (최근)";
    }

    List history = json.decode(p.getString('history_logs') ?? "[]");
    for (var c in contacts) {
      if (c['number'] != null) {
        String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
        try {
          await BackgroundSms.sendMessage(phoneNumber: cleanNumber, message: "[안심지키미] 응답이 없어 연락드립니다.\n좌표: $locationStr\n구글맵에서 확인 바랍니다.");
          history.insert(0, {'type': '비상 알림', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '${c['name']}님에게 문자 발송'});
        } catch (_) {}
      }
    }
    await p.setString('history_logs', json.encode(history.take(30).toList()));
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());
    _historyKey.currentState?.loadLogs();
  }

  void _showDetailedGuide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("⚠️ 필수 안내 사항", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: ListBody(
            children: [
              Text("앱 종료 시 주의사항", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
              SizedBox(height: 8),
              Text("최근 앱 목록에서 앱을 완전히 종료(스와이프)하면 백그라운드 서비스가 차단되어 비상 문자가 발송되지 않습니다. 반드시 앱을 종료하지 말고 백그라운드 상태로 유지해 주세요.", 
                style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.5)),
              Divider(height: 20),
              Text("1. 위치 권한: [항상 허용]", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text("2. 배터리 설정: [제한 없음]", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text("3. SMS 권한: [허용]", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { 
              Navigator.pop(context); 
              [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts, Permission.notification].request();
            }, 
            child: const Text("확인했습니다", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(channelId: 'safety_service', channelName: '안심 지키미', channelImportance: NotificationChannelImportance.MAX, priority: NotificationPriority.HIGH),
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
            selectedFontSize: 11,
            unselectedFontSize: 11,
            onTap: (index) {
              setState(() => _currentIndex = index);
              if (index == 1) _historyKey.currentState?.loadLogs();
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 22), label: '홈'),
              BottomNavigationBarItem(icon: Icon(Icons.history, size: 22), label: '기록'),
              BottomNavigationBarItem(icon: Icon(Icons.settings, size: 22), label: '설정'),
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
  String _lastCheckIn = "안부를 전해주세요";
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
      _lastCheckIn = p.getString('lastCheckIn') ?? "안부를 전해주세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 30),
          const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [0, 1, 12, 24].map((h) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 11)),
                selected: _selectedHours == h,
                onSelected: (v) async {
                  setState(() => _selectedHours = h);
                  (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                },
              ),
            )).toList(),
          ),
          const Spacer(),
          Text("마지막 체크인: $_lastCheckIn", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 25),
          GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) async {
              setState(() => _isPressed = false);
              String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
              final p = await SharedPreferences.getInstance();
              await p.setString('lastCheckIn', now);
              await p.remove('lastEmergencySent');
              List history = json.decode(p.getString('history_logs') ?? "[]");
              history.insert(0, {'type': '체크인', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 확인 완료'});
              await p.setString('history_logs', json.encode(history.take(30).toList()));
              setState(() => _lastCheckIn = now);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,
                border: Border.all(color: const Color(0xFFFFD1DC), width: 4),
                boxShadow: _isPressed ? [] : [const BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(5, 5))],
              ),
              child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.face, size: 100, color: Colors.orange))),
            ),
          ),
          const Spacer(flex: 2),
          const Text("앱 종료 시 안심 서비스가 작동하지 않습니다.", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
          const SizedBox(height: 20),
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
    if (mounted) setState(() => _logs = json.decode(p.getString('history_logs') ?? "[]"));
  }
  @override
  void initState() { super.initState(); loadLogs(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("활동 기록", style: TextStyle(fontSize: 16))),
    body: ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, i) => ListTile(
        title: Text(_logs[i]['type'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(_logs[i]['msg'], style: const TextStyle(fontSize: 11)),
        trailing: Text(_logs[i]['time'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
    if (mounted) setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");
      _autoOn = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("환경 설정", style: TextStyle(fontSize: 16))),
    body: Column(
      children: [
        SwitchListTile(
          title: const Text("실시간 감시 모드", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: const Text("백그라운드에서 안부를 체크합니다.", style: TextStyle(fontSize: 11)),
          value: _autoOn,
          // 스위치 크기는 그대로 유지
          onChanged: (v) async {
            final p = await SharedPreferences.getInstance();
            await p.setBool('auto_sms_enabled', v);
            setState(() => _autoOn = v);
            if (v) {
              await FlutterForegroundTask.startService(notificationTitle: "안심 서비스 가동 중", notificationText: "보호 모드가 활성화되었습니다.", callback: startCallback);
            } else {
              await FlutterForegroundTask.stopService();
            }
          },
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 13)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: () async {
              if (await Permission.contacts.request().isGranted) {
                final c = await ContactsService.openDeviceContactPicker();
                if (c != null && c.phones!.isNotEmpty) {
                  setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
                  (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                }
              }
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            child: const Text("보호자 연락처 추가", style: TextStyle(fontSize: 13)),
          ),
        )
      ],
    ),
  );
}
