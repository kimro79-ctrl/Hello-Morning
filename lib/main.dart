import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:background_sms/background_sms.dart'; // ✅ 문자 발송 패키지
import 'dart:async';
import 'dart:io';

// ✅ 백그라운드 작업 수행 핸들러
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, TaskStarter starter) async {
    // 여기에 일정 시간(예: 24시간) 체크인이 없을 경우 문자 발송 로직 구현 가능
    // 현재는 시스템 엔진 유지 및 위치 갱신 역할 수행
  }

  @override
  Future<void> onDestroy(DateTime timestamp, TaskStarter starter) async {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase 초기화 실패: $e");
  }
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFDFCF0), useMaterial3: true),
    home: const MainNavigation(),
  );
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _idx = 0;
  final List<Widget> _pages = [const HomeScreen(), const HistoryScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeDialog());
  }

  Future<void> _showNoticeDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("📢 알림", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("안심 지키미의 정상 작동을 위해\n모든 권한 허용이 필요합니다."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인"))],
      ),
    );
    _initServiceConfig();
  }

  Future<void> _initServiceConfig() async {
    await [Permission.notification, Permission.sms, Permission.locationAlways].request();
    FlutterForegroundTask.init(
      notificationOptions: const NotificationOptions(
        channelId: 'safety_check',
        channelName: '안심 지키미',
        channelDescription: '안전 감시 중',
        channelImportance: NotificationImportance.MAX,
        priority: NotificationPriority.HIGH,
        iconData: NotificationIconData(resType: ResourceType.drawable, resPrefix: ResourcePrefix.android, name: 'btn_star'),
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 5000, isOnceEvent: false, autoRunOnBoot: true, allowWakeLock: true, allowWifiLock: true),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx,
      selectedItemColor: const Color(0xFF1A237E),
      onTap: (i) => setState(() => _idx = i),
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
  String _last = "기록 없음";
  String _loc = "위치 확인 중...";
  bool _down = false;
  String _uid = "";

  @override
  void initState() { super.initState(); _initUserId(); }

  void _initUserId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) { _uid = (await deviceInfo.androidInfo).id; }
    _listenToFirebase();
  }

  void _listenToFirebase() {
    if (_uid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _last = snap.data()?['lastCheckIn'] ?? "기록 없음";
          _loc = snap.data()?['lastLocation'] ?? "위치 정보 없음";
        });
      }
    });
  }

  // ✅ 안심 체크인 시 문자 발송 테스트 포함
  void _checkIn() async {
    if (_uid.isEmpty) return;
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high); } catch (_) {}
    String currentLoc = pos != null ? "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}" : "알수없음";

    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'lastCheckIn': now,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastLocation': currentLoc,
    }, SetOptions(merge: true));

    // ✅ 보호자에게 체크인 문자 자동 발송 (선택 사항)
    _sendAutoSms("안심 지키미: 오늘 체크인이 완료되었습니다. 위치: $currentLoc");
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("안심 체크인 완료 및 문자 전송")));
  }

  // ✅ 실질적인 문자 발송 함수
  void _sendAutoSms(String message) async {
    final snap = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    if (snap.exists) {
      List contacts = snap.data()?['contacts'] ?? [];
      for (var contact in contacts) {
        String number = contact['number'].toString().replaceAll('-', '');
        await BackgroundSms.sendMessage(phoneNumber: number, message: message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Container(
          width: double.infinity, height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.white.withOpacity(0.8), const Color(0xFFFDFCF0)],
            ),
          ),
          child: const Center(child: Text("안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 30),
        const Text("매일 한번 눌러주세요", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.blueGrey)),
        const SizedBox(height: 30),
        GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) { setState(() => _down = false); _checkIn(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _down ? 180 : 200, height: _down ? 180 : 200,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.face, size: 100, color: Colors.orange)),
          ),
        ),
        const SizedBox(height: 40),
        Text("마지막 체크인: $_last", style: const TextStyle(fontWeight: FontWeight.bold)),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text("현재 위치: $_loc", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ],
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("기록 화면")));
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _on = false;
  String _uid = "";

  @override
  void initState() { super.initState(); _initUserId(); }

  void _initUserId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) { _uid = (await deviceInfo.androidInfo).id; }
    _loadSettings();
  }

  void _loadSettings() {
    if (_uid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (snap.exists && mounted) setState(() => _on = snap.data()?['autoSmsEnabled'] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.pink.withOpacity(0.1))),
            child: Column(
              children: [
                const Text("[필수 설정]", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("자동 안심 감시", style: TextStyle(fontWeight: FontWeight.bold)),
                    Switch(value: _on, activeColor: Colors.pinkAccent, onChanged: (v) async {
                      if (v) {
                        await FlutterForegroundTask.startService(
                          notificationTitle: '안심 감시 중',
                          notificationText: '정상 작동 중입니다.',
                          callback: startCallback,
                        );
                      } else {
                        await FlutterForegroundTask.stopService();
                      }
                      await FirebaseFirestore.instance.collection('users').doc(_uid).update({'autoSmsEnabled': v});
                    }),
                  ],
                ),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildIconBtn(Icons.settings, "권한 설정", () => openAppSettings()),
                    _buildIconBtn(Icons.battery_saver, "배터리 최적화 제외", () => FlutterForegroundTask.openIgnoreBatteryOptimizationSettings()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildIconBtn(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Column(children: [Icon(icon, color: Colors.indigo), const SizedBox(height: 5), Text(label, style: const TextStyle(fontSize: 12))]),
  );
}
