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
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    _runSafetyCheck();
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    _runSafetyCheck();
  }

  Future<void> _runSafetyCheck() async {
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
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        List contacts = json.decode(contactsJson);
        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[1인가구 안심 지키미] 응답 지연 발생!\n위치: http://maps.google.com/?q=${pos.latitude},${pos.longitude}"
          );
        }
        await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
      } catch (e) {
        debugPrint("전송 에러: $e");
      }
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}
  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

void main() async {
  // ✅ 앱 시작 전 초기화 보장
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
  final List<Widget> _screens = [const HomeScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    // ✅ 앱이 완전히 켜진 후 초기화 하도록 변경 (충돌 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initForegroundTask();
      _showNoticeDialog();
    });
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_channel',
        channelName: '안심 지키미 서비스',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 300000,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("필수 권한 안내", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("원활한 보호 시스템 작동을 위해 위치(항상 허용)와 SMS 권한이 필요합니다."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermissions();
            },
            child: const Text("확인 및 설정"),
          )
        ],
      ),
    );
  }

  Future<void> _requestPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location].request();
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
    // 권한 획득 후 서비스 시작
    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        notificationTitle: '안심 지키미 작동 중',
        notificationText: '백그라운드에서 안전을 확인하고 있습니다.',
        callback: startCallback,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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

// --- HomeScreen & SettingScreen 은 기존 디자인 유지 ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  String _locationInfo = "위치 확인 중...";
  int _selectedHours = 1;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(_controller);
    _loadData();
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _locationInfo = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}");
    } catch (e) {
      if (mounted) setState(() => _locationInfo = "위치 확인 불가");
    }
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Center(child: Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0)))),
              const SizedBox(height: 8),
              Text(_locationInfo, style: const TextStyle(color: Color(0xFF5C6BC0), fontSize: 12)),
              const SizedBox(height: 25),
              Wrap(
                spacing: 6,
                children: [0, 1, 12, 24].map((h) => ChoiceChip(
                  label: Text(h == 0 ? "5분" : "$h시간"),
                  selected: _selectedHours == h,
                  onSelected: (v) async {
                    setState(() => _selectedHours = h);
                    (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                  },
                )).toList(),
              ),
              const Spacer(flex: 2),
              Text(_lastCheckIn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 30),
              GestureDetector(
                onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
                onTapUp: (_) async {
                  setState(() => _isPressed = false); _controller.reverse();
                  String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                  final p = await SharedPreferences.getInstance();
                  await p.setString('lastCheckIn', now);
                  setState(() => _lastCheckIn = now);
                },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
                    child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.face, size: 100, color: Colors.orange))),
                  ),
                ),
              ),
              const Spacer(flex: 3),
              const Text("미응답 시 보호자에게 위치가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: 40),
            ],
          ),
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
      appBar: AppBar(title: const Text("설정"), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("자동 문자 전송 활성화"),
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
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text("보호자 추가"),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
