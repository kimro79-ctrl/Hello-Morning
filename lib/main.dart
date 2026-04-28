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

// 1. 백그라운드 작업 핸들러 (Isolate 내에서 실행됨)
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

    // 설정된 시간이 지났는지 확인
    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      try {
        // 위치 정보 획득
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        
        List contacts = json.decode(contactsJson);
        for (var c in contacts) {
          if (c['number'] != null) {
            // ✅ 백그라운드 문자 발송 실행
            await BackgroundSms.sendMessage(
              phoneNumber: c['number'],
              message: "[안심 지키미] 응답 지연 발생!\n위치: http://maps.google.com/?q=${pos.latitude},${pos.longitude}",
            );
          }
        }

        // 중복 발송 방지를 위해 체크인 시간 강제 갱신
        await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
        
        // 기록 추가
        List history = json.decode(p.getString('history_logs') ?? "[]");
        history.insert(0, {'type': '비상 알림', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '백그라운드 문자 발송 완료'});
        await p.setString('history_logs', json.encode(history.take(30).toList()));
        
      } catch (e) {
        print("백그라운드 작업 에러: $e");
      }
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
        channelName: '안심 지키미 서비스',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 60000, // 1분마다 체크
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
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
  String _locationInfo = "좌표 확인 중...";
  int _selectedHours = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
    _updateLocation();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "체크인이 필요합니다";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  Future<void> _updateLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _locationInfo = "현재 좌표: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}");
      }
    } catch (e) {
      if (mounted) setState(() => _locationInfo = "위치 권한을 허용해 주세요");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 30),
          const Text("안심 지키미", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
          Text(_locationInfo, style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
          Text("마지막 체크인: $_lastCheckIn"),
          const SizedBox(height: 30),
          GestureDetector(
            onTap: () async {
              String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
              final p = await SharedPreferences.getInstance();
              await p.setString('lastCheckIn', now);
              
              List history = json.decode(p.getString('history_logs') ?? "[]");
              history.insert(0, {'type': '체크인', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 확인 완료'});
              await p.setString('history_logs', json.encode(history.take(30).toList()));
              
              setState(() => _lastCheckIn = now);
              _updateLocation();
            },
            child: Image.asset('assets/smile.png', width: 220, errorBuilder: (c,e,s) => const Icon(Icons.face, size: 220, color: Colors.orange)),
          ),
          const Spacer(),
          const Text("미응답 시 보호자에게 비상 문자가 발송됩니다.", style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 40),
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
    body: _logs.isEmpty ? const Center(child: Text("기록이 없습니다.")) : ListView.builder(
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
                await FlutterForegroundTask.startService(
                  notificationTitle: '안심 지키미 작동 중',
                  notificationText: '미응답 시 문자를 발송합니다.',
                  callback: startCallback,
                );
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
              child: const Text("보호자 추가"),
            ),
          ),
        ],
      ),
    );
  }
}
