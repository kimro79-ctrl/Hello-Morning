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

// ✅ 포그라운드 서비스 핸들러 (백그라운드 문자 발송 핵심)
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
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        List contacts = json.decode(contactsJson);
        String mapsUrl = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";

        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심 지키미] 응답 지연 발생!\n위치 확인: $mapsUrl"
          );
        }
        await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
      } catch (e) {
        debugPrint("전송 오류: $e");
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
        channelDescription: '보호 중입니다.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 180000,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Column(
          children: [
            Icon(Icons.shield_rounded, color: Color(0xFFFF8A65), size: 50),
            SizedBox(height: 10),
            Text("안심 지키미 안내", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("서비스 이용을 위해 아래 권한이 필요합니다.", style: TextStyle(fontSize: 14, color: Colors.grey)),
            SizedBox(height: 15),
            Text("✅ 위치: 항상 허용 (위치 자동 전송)", style: TextStyle(fontWeight: FontWeight.w600)),
            Text("✅ SMS: 발송 허용 (비상 연락용)", style: TextStyle(fontWeight: FontWeight.w600)),
            Text("✅ 알림: 서비스 실행 상태 유지", style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 15),
            Text("* 설정한 시간 동안 응답이 없으면 보호자에게 문자가 자동으로 전송됩니다.", style: TextStyle(fontSize: 12, color: Colors.redAccent)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A65),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: () { Navigator.pop(context); _initPermissions(); },
              child: const Text("동의하고 시작하기"),
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
  String _locationInfo = "위치 확인 중...";
  int _selectedHours = 1;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.93).animate(_controller);
    _loadData();
    _updateLocation();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 첫 확인을 눌러주세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  Future<void> _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _locationInfo = "현재 위치: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");
    } catch (_) {
      if (mounted) setState(() => _locationInfo = "위치 정보 권한이 필요합니다");
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
          stops: [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 50),
              const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF37474F))),
              const SizedBox(height: 8),
              Text(_locationInfo, style: const TextStyle(color: Color(0xFF78909C), fontSize: 13)),
              const SizedBox(height: 35),
              
              // ✅ 시간 선택 배너 디자인 개선
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]
                ),
                child: Column(
                  children: [
                    const Text("미응답 알림 간격", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF546E7A))),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [0, 1, 12, 24].map((h) => ChoiceChip(
                        label: Text(h == 0 ? "5분" : "$h시간", style: TextStyle(color: _selectedHours == h ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                        selected: _selectedHours == h,
                        selectedColor: const Color(0xFFFF8A65),
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _selectedHours == h ? Colors.transparent : Colors.grey.shade200)),
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
              Text("최근 확인 시간: $_lastCheckIn", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF455A64))),
              const SizedBox(height: 30),
              
              GestureDetector(
                onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
                onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 220, height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: _isPressed ? const Color(0xFFFF8A65).withOpacity(0.5) : Colors.black.withOpacity(0.08),
                          blurRadius: _isPressed ? 40 : 25, spreadRadius: _isPressed ? 10 : 2,
                        )
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/smile.png',
                        fit: BoxFit.cover,
                        errorBuilder: (c,e,s) => const Icon(Icons.face_retouching_natural, size: 130, color: Colors.orangeAccent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 50),
              const Text("무사히 있다면 버튼을 꾹 눌러주세요", style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13)),
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
    return WithForegroundTask(
      child: Scaffold(
        body: Column(
          children: [
            // ✅ 설정 화면 상단 예쁜 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 70, bottom: 40, left: 25, right: 25),
              decoration: const BoxDecoration(
                color: Color(0xFFFF8A65),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("서비스 설정", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(
                    _autoSmsEnabled ? "✅ 안심 지키미가 작동 중입니다" : "❌ 서비스를 켜서 안전을 확보하세요",
                    style: const TextStyle(color: Colors.whiteEms, fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text("자동 문자 전송 활성화", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              subtitle: const Text("미응답 시 등록된 연락처로 자동 전송"),
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
                      notificationText: '실시간으로 당신의 안전을 체크합니다.',
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
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
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
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text("보호자 추가하기", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C6BC0), 
                    foregroundColor: Colors.white,
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
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
