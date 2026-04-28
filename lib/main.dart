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

// ✅ 백그라운드 전용 일꾼 (TaskHandler)
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

    // 현재 시간과 마지막 체크인 시간 비교
    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        List contacts = json.decode(contactsJson);
        // ✅ 구글맵 링크 오타 수정 (0{pos... -> ${pos...)
        String mapsUrl = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";

        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심 지키미] 응답 지연 발생!\n위치 확인: $mapsUrl"
          );
        }
        // 문자 발송 후 체크인 시간 갱신 (중복 발송 방지)
        await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
      } catch (e) {
        debugPrint("전송 실패: $e");
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
      scaffoldBackgroundColor: const Color(0xFFFDFCF0),
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
    _initForegroundTask();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNoticeDialog());
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check',
        channelName: '안심 지키미 서비스',
        channelDescription: '사용자의 안전을 실시간으로 확인합니다.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 180000, // 3분마다 체크
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.security, color: Color(0xFFFF8A65), size: 45),
            SizedBox(height: 12),
            Text("안심 지키미 보호 안내", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("안전한 보호를 위해 다음 설정이 필요합니다.\n", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text("📍 위치: '항상 허용' (백그라운드 전송용)"),
            Text("🔋 배터리 최적화: '제외' (중단 없는 실행)"),
            Text("💬 SMS: 발송 허용 (비상 연락용)"),
            SizedBox(height: 10),
            Text("* 미응답 시 보호자에게 자동으로 위치가 전송됩니다.", style: TextStyle(fontSize: 12, color: Colors.redAccent)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A65),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              onPressed: () { Navigator.pop(context); _initPermissions(); },
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Text("설정 완료")),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _initPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location, Permission.notification].request();
    if (await Permission.location.isGranted) await Permission.locationAlways.request();
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
  String _locationInfo = "위치 정보를 불러오는 중...";
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
      if (mounted) setState(() => _locationInfo = "위치: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFE0F2F1), Color(0xFFFDFCF0)],
          stops: [0.0, 0.35],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 50),
              const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF37474F))),
              const SizedBox(height: 8),
              Text(_locationInfo, style: const TextStyle(color: Color(0xFF78909C), fontSize: 13)),
              const SizedBox(height: 40),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white)
                ),
                child: Column(
                  children: [
                    const Text("미응답 시 문자 전송 주기", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF546E7A))),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [0, 1, 12, 24].map((h) => ChoiceChip(
                        label: Text(h == 0 ? "5분" : "$h시간", style: TextStyle(color: _selectedHours == h ? Colors.white : Colors.black87)),
                        selected: _selectedHours == h,
                        selectedColor: const Color(0xFFFF8A65),
                        backgroundColor: Colors.white,
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide.none,
                        onSelected: (v) async {
                          setState(() => _selectedHours = h);
                          (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                        },
                      )).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
              Text("마지막 안부: $_lastCheckIn", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF455A64))),
              const SizedBox(height: 35),
              GestureDetector(
                onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
                onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 210, height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: _isPressed ? const Color(0xFFFF8A65).withOpacity(0.5) : Colors.black.withOpacity(0.06),
                          blurRadius: _isPressed ? 35 : 20, spreadRadius: _isPressed ? 12 : 2,
                        )
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/smile.png',
                        fit: BoxFit.cover,
                        errorBuilder: (c,e,s) => const Icon(Icons.face, size: 120, color: Colors.orangeAccent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 45),
              const Text("무사히 하루를 보내고 있다면 버튼을 눌러주세요", style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13)),
              const SizedBox(height: 30),
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
    return WithForegroundTask(
      child: Scaffold(
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 70, bottom: 40, left: 30, right: 30),
              decoration: const BoxDecoration(
                color: Color(0xFFFF8A65),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("보호자 및 서비스 설정", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    _autoSmsEnabled ? "현재 실시간 보호 기능이 켜져 있습니다." : "안전 보호를 위해 스위치를 켜주세요.",
                    style: const TextStyle(color: Colors.whiteEms, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text("자동 문자 전송 활성화", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("일정 시간 미응답 시 등록된 보호자에게 문자를 보냅니다."),
              value: _autoSmsEnabled,
              activeColor: const Color(0xFFFF8A65),
              onChanged: (v) async {
                final p = await SharedPreferences.getInstance();
                await p.setBool('auto_sms_enabled', v);
                setState(() => _autoSmsEnabled = v);
                if (v) {
                  if (!await FlutterForegroundTask.isRunningService) {
                    FlutterForegroundTask.startService(
                      notificationTitle: '안심 지키미 작동 중',
                      notificationText: '사용자의 안전을 확인하고 있습니다.',
                      callback: startCallback,
                    );
                  }
                } else {
                  FlutterForegroundTask.stopService();
                }
              },
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider()),
            Expanded(
              child: _contacts.isEmpty 
                ? const Center(child: Text("등록된 보호자가 없습니다.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    itemCount: _contacts.length,
                    itemBuilder: (c, i) => Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.grey.shade200)),
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Color(0xFFF1F8E9), child: Icon(Icons.person, color: Color(0xFF4CAF50))),
                        title: Text(_contacts[i]['name'] ?? '보호자', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(_contacts[i]['number'] ?? ''),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async {
                          setState(() => _contacts.removeAt(i));
                          (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                        }),
                      ),
                    ),
                  ),
            ),
            Padding(
              padding: const EdgeInsets.all(25),
              child: SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text("보호자 등록하기", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C6BC0), 
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))
                  ),
                  onPressed: () async {
                    if (await Permission.contacts.request().isGranted) {
                      final c = await ContactsService.openDeviceContactPicker();
                      if (c != null && c.phones!.isNotEmpty) {
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
