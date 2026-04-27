import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // ✅ 에러 해결을 위한 필수 임포트
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

// ✅ 포그라운드 작업 핸들러 (앱 종료 시에도 동작)
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    int selectedHours = p.getInt('selectedHours') ?? 1;

    if (last == null || contactsJson == null || contactsJson == "[]") return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      List contacts = json.decode(contactsJson);
      String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";

      for (var c in contacts) {
        await BackgroundSms.sendMessage(
          phoneNumber: c['number'],
          message: "[안심 지키미] 응답 지연 발생!\n위치 확인: $googleMapsUrl"
        );
      }
      // 발송 후 자동 갱신으로 중복 발송 방지
      await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
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
      [span_0](start_span)scaffoldBackgroundColor: const Color(0xFFF5F5DC), // ✅ 원본 아이보리 유지[span_0](end_span)
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
    _initForegroundTask(); // ✅ 서비스 초기화 호출
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _[span_1](start_span)showNoticeDialog(); // ✅ 권한 안내 다이얼로그[span_1](end_span)
    });
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_channel',
        channelName: '안심 지키미 서비스',
        channelDescription: '사용자의 안전 상태를 실시간으로 모니터링합니다.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 180000, // ✅ 3분 주기
        isOnceEvent: false,
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
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFFF8A65)),
            SizedBox(width: 10),
            Text("필수 기능 안내", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("보호를 위해 백그라운드 위치(항상 허용)와 SMS 발송 권한이 반드시 필요합니다."),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _initPermissions(); },
            child: const Text("확인 및 설정", style: TextStyle(color: Color(0xFF5C6BC0), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _initPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location, Permission.notification].request();
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
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

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  Future<void> _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _locationInfo = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}");
    } catch (_) {
      if (mounted) setState(() => _locationInfo = "위치 확인 불가");
    }
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
    _updateLocation();
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
            [span_2](start_span)colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)], // ✅ 그라데이션[span_2](end_span)
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
                  label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 11)),
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
                onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          [span_3](start_span)color: _isPressed ? const Color(0xFFFFC1CC).withOpacity(0.6) : Colors.black.withOpacity(0.03), // ✅ 핑크 그림자[span_3](end_span)
                          blurRadius: _isPressed ? 25 : 15, spreadRadius: _isPressed ? 8 : 1,
                        )
                      ],
                    ),
                    [span_4](start_span)child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.face, size: 100, color: Colors.orange))), // ✅ smile.png 원상복구[span_4](end_span)
                  ),
                ),
              ),
              const Spacer(flex: 3),
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
    return WithForegroundTask( // ✅ 포그라운드 위젯 (임포트 완료)
      child: Scaffold(
        appBar: AppBar(title: const Text("보호자 설정", style: TextStyle(fontSize: 16)), backgroundColor: Colors.transparent, centerTitle: true, elevation: 0),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFE0B2).withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("권한 설정 확인", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const Text("위치 권한을 '항상 허용'으로 설정해야 보호가 가능합니다.", style: TextStyle(fontSize: 11)),
                        const SizedBox(height: 4),
                        InkWell(onTap: () => openAppSettings(), child: const Text("설정 바로가기 >", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text("자동 문자 전송 활성화", style: TextStyle(fontSize: 14)),
              value: _autoSmsEnabled,
              activeColor: const Color(0xFFFF7043),
              onChanged: (v) async {
                final p = await SharedPreferences.getInstance();
                await p.setBool('auto_sms_enabled', v);
                setState(() => _autoSmsEnabled = v);
                
                if (v) {
                  if (!await FlutterForegroundTask.isRunningTask) {
                    FlutterForegroundTask.startService(notificationTitle: '안심 지키미 작동 중', notificationText: '당신의 안전을 확인하고 있습니다.', callback: startCallback);
                  }
                } else {
                  FlutterForegroundTask.stopService();
                }
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _contacts.length,
                itemBuilder: (c, i) => ListTile(
                  dense: true,
                  leading: const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
                  title: Text(_contacts[i]['name'] ?? '이름 없음', style: const TextStyle(fontSize: 13)),
                  subtitle: Text(_contacts[i]['number'] ?? '', style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), onPressed: () async {
                    setState(() => _contacts.removeAt(i));
                    (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text("보호자 추가"),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
      ),
    );
  }
}
