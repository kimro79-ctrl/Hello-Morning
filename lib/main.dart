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
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();
    await p.reload(); 

    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    int selectedHours = p.getInt('selectedHours') ?? 1;

    if (last == null || contactsJson == null || contactsJson == "[]") return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        List contacts = json.decode(contactsJson);
        
        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심 지킴이] 응답 없음! 위치 확인:\nhttp://google.com/maps?q=${pos.latitude},${pos.longitude}"
          );
        }

        String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        await p.setString('lastCheckIn', now);
        
        FlutterForegroundTask.updateService(
          notificationTitle: '안심 지킴이',
          notificationText: '최근 체크 완료: $now',
        );
      } catch (e) {
        debugPrint("백그라운드 에러: $e");
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: const Color(0xFFFFFDF9), // 기존 미색 배경 유지
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFFFF8A65), // 기존 주황색 포인트 유지
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
  final List<Widget> _screens = [const HomeScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startServiceWithPermissions());
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_service',
        channelName: '안심 지킴이 감시 서비스',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 180000, // 3분 반복
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startServiceWithPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location, Permission.notification].request();
    await Permission.locationAlways.request();
    await Permission.ignoreBatteryOptimizations.request();

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        notificationTitle: '안심 지키미 작동 중',
        notificationText: '실시간으로 안전을 확인하고 있습니다.',
        callback: startCallback,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFFFF8A65),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  int _selectedHours = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Text("안심 지키미", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
            const SizedBox(height: 25),
            Wrap(
              spacing: 8,
              children: [0, 1, 12, 24].map((h) => ChoiceChip(
                label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 11)),
                selected: _selectedHours == h,
                onSelected: (v) async {
                  setState(() => _selectedHours = h);
                  (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                },
              )).toList(),
            ),
            const Spacer(),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _updateCheckIn,
              child: Container(
                width: 180, height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, 
                  color: Colors.white, 
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]
                ),
                child: const Icon(Icons.face_retouching_natural, size: 80, color: Colors.orangeAccent), // 기존 아이콘 유지
              ),
            ),
            const Spacer(flex: 2),
            const Text("미응답 시 보호자에게 위치가 발송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  List _contacts = [];
  bool _autoSmsEnabled = false;

  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");
      _autoSmsEnabled = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontSize: 16)), centerTitle: true),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("자동 문자 발송 활성화"),
            value: _autoSmsEnabled,
            activeColor: const Color(0xFFFF8A65),
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('auto_sms_enabled', v);
              setState(() => _autoSmsEnabled = v);
            },
          ),
          const Divider(),
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name'] ?? '이름 없음'),
              subtitle: Text(_contacts[i]['number'] ?? '번호 없음'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  setState(() => _contacts.removeAt(i));
                  (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                }
              ),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white),
                onPressed: () async {
                  if (await Permission.contacts.request().isGranted) {
                    final c = await ContactsService.openDeviceContactPicker();
                    if (c != null) {
                      setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
                      (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                    }
                  }
                },
                child: const Text("보호자 연락처 추가"),
              ),
            ),
          )
        ],
      ),
    );
  }
}
