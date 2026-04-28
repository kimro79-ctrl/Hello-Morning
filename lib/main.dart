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

// 백그라운드 작업 핸들러
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SafetyTaskHandler());
}

class SafetyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null || contactsJson == "[]") return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int selectedHours = p.getInt('selectedHours') ?? 1;
    int limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      // 위치 획득 및 문자 발송
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List contacts = json.decode(contactsJson);
      for (var c in contacts) {
        await BackgroundSms.sendMessage(
          phoneNumber: c['number'],
          message: "[안심 지키미] 응답 지연 발생! 위급 상황일 수 있습니다.\n위치: https://www.google.com/maps?q=${pos.latitude},${pos.longitude}",
        );
      }
      
      // 기록 저장
      List history = json.decode(p.getString('history_logs') ?? "[]");
      history.insert(0, {'type': '비상 알림', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '보호자에게 비상 문자 발송 완료'});
      await p.setString('history_logs', json.encode(history.take(20).toList()));
      
      // 발송 후 체크인 시간 초기화 (중복 발송 방지)
      await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
    }
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
  final List<Widget> _screens = [const HomeScreen(), const HistoryScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_service',
        channelName: '안심 지키미 보호 서비스',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 60000, isOnceEvent: false, autoRunOnBoot: true),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: const Color(0xFFFF8A65),
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
          ],
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  String _locationInfo = "위치 확인 중...";
  int _selectedHours = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _locationInfo = "현재: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 30),
          const Text("안심 지키미", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
          Text(_locationInfo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [0, 1, 12, 24].map((h) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
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
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
              final p = await SharedPreferences.getInstance();
              await p.setString('lastCheckIn', now);
              
              List history = json.decode(p.getString('history_logs') ?? "[]");
              history.insert(0, {'type': '체크인', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 확인 완료'});
              await p.setString('history_logs', json.encode(history.take(20).toList()));
              
              setState(() => _lastCheckIn = now);
              _updateLocation();
            },
            child: Image.asset('assets/smile.png', width: 200, errorBuilder: (c,e,s) => const Icon(Icons.face, size: 200, color: Colors.orange)),
          ),
          const Spacer(),
          const Text("미응답 시 보호자에게 위치가 전송됩니다.", style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List _logs = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _logs = json.decode(p.getString('history_logs') ?? "[]"));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("활동 기록")),
    body: ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (c, i) => ListTile(
        leading: Icon(_logs[i]['type'] == '체크인' ? Icons.check_circle : Icons.warning, color: _logs[i]['type'] == '체크인' ? Colors.green : Colors.red),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정")),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("실시간 감시 모드"),
            subtitle: const Text("백그라운드에서 상시 감시"),
            value: _autoOn,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('auto_sms_enabled', v);
              setState(() => _autoOn = v);
              if (v) {
                if (await FlutterForegroundTask.isRunningService) {
                  await FlutterForegroundTask.restartService();
                } else {
                  await FlutterForegroundTask.startService(notificationTitle: '안심 지키미', notificationText: '실시간 보호 중', callback: startCallback);
                }
              } else {
                await FlutterForegroundTask.stopService();
              }
            },
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(_contacts[i]['name']),
                subtitle: Text(_contacts[i]['number']),
                trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
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
                  if (c != null) {
                    setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
                    (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                  }
                }
              },
              child: const Text("연락처 추가"),
            ),
          ),
        ],
      ),
    );
  }
}
