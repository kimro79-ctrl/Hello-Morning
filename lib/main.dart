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
      
      int diffMin = DateTime.now().difference(lastTime).inMinutes;

      // 설정 시간 경과 시
      if (diffMin >= limitMin) {
        String? lastSentStr = p.getString('lastEmergencySent');
        if (lastSentStr != null) {
          DateTime lastSentTime = DateTime.parse(lastSentStr);
          // 마지막 발송으로부터 5분 경과 여부 확인 (반복 발송 핵심)
          if (DateTime.now().difference(lastSentTime).inMinutes >= 5) {
            sendPort?.send('SEND_SMS_ACTION');
          }
        } else {
          // 최초 발송
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
  final List<Widget> _screens = [const HomeScreen(), const HistoryScreen(), const SettingScreen()];
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
    _bindReceivePort();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
      _showNoticeDialog();
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
      // [수정] 정밀도를 Medium으로 하향하여 실내 응답 속도 개선
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, 
        timeLimit: const Duration(seconds: 5),
      );
      locationStr = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {
      Position? lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        locationStr = "${lastPos.latitude.toStringAsFixed(6)}, ${lastPos.longitude.toStringAsFixed(6)} (최근)";
      }
    }

    List history = json.decode(p.getString('history_logs') ?? "[]");

    for (var c in contacts) {
      if (c['number'] != null) {
        String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
        try {
          await BackgroundSms.sendMessage(
            phoneNumber: cleanNumber,
            message: "[안심지키미] 응답이 없어 연락드립니다.\n좌표: $locationStr\n구글맵에서 좌표확인 부탁합니다.",
          );
          
          history.insert(0, {
            'type': '비상 알림',
            'time': DateFormat('MM/dd HH:mm').format(DateTime.now()),
            'msg': '보호자(${c['name']})에게 안심 문자 재발송 완료'
          });
        } catch (e) {
          history.insert(0, {'type': '에러', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': 'SMS 전송 실패'});
        }
      }
    }

    await p.setString('history_logs', json.encode(history.take(30).toList()));
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());
    if (mounted) setState(() {});
  }

  Future<void> _initialSetup() async {
    await [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts, Permission.notification].request();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ 필수 설정 안내", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          "1. 위치 권한: '항상 허용'\n"
          "2. 위치 정확도: '대략적인 위치' 확인\n"
          "3. SMS: '자동권한설정' 클릭\n"
          "4. 배터리: '제한 없음' 설정\n\n"
          "미응답 시 5분마다 문자가 재발송됩니다.",
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인"))],
      ),
    );
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_v34',
        channelName: '안심 지키미 서비스',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 60000, autoRunOnBoot: true, allowWakeLock: true),
    );
  }

  @override
  Widget build(BuildContext context) => WithForegroundTask(
        child: Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: const Color(0xFFFF8A65),
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
              BottomNavigationBarItem(icon: Icon(Icons.history_edu), label: '기록'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '설정'),
            ],
          ),
        ),
      );
}

// --- UI 코드 (디자인 유지) ---

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "안부를 전해주세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _locationInfo = "현재: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)],
          stops: [0.0, 0.45],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Text("안심 지키미", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
            const SizedBox(height: 5),
            Text(_locationInfo, style: const TextStyle(color: Color(0xFF78909C), fontSize: 12)),
            const SizedBox(height: 35),
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
            const Spacer(flex: 2),
            Text("마지막 체크인: $_lastCheckIn", style: const TextStyle(fontSize: 15, color: Colors.brown, fontWeight: FontWeight.w600)),
            const SizedBox(height: 30),
            GestureDetector(
              onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
              onTapUp: (_) async {
                setState(() => _isPressed = false); _controller.reverse();
                String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                final p = await SharedPreferences.getInstance();
                await p.setString('lastCheckIn', now);
                await p.remove('lastEmergencySent'); // 발송 타이머 초기화
                
                List history = json.decode(p.getString('history_logs') ?? "[]");
                history.insert(0, {'type': '활동 체크', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 안부 확인 완료'});
                await p.setString('history_logs', json.encode(history.take(30).toList()));
                
                setState(() => _lastCheckIn = now);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("체크 완료! 좋은 하루 되세요.")));
              },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 210, height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    boxShadow: [BoxShadow(color: _isPressed ? Colors.orangeAccent.withOpacity(0.5) : Colors.black12, blurRadius: 25)],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/smile.png', fit: BoxFit.cover, 
                      errorBuilder: (c, e, s) => const Icon(Icons.face, size: 120, color: Colors.orange)),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 3),
            const Text("미응답 시 설정된 연락처로 위치 정보가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 30),
          ],
        ),
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
    appBar: AppBar(title: const Text("활동 및 알림 기록"), backgroundColor: Colors.transparent),
    body: _logs.isEmpty 
      ? const Center(child: Text("기록이 없습니다."))
      : ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, i) => ListTile(
            leading: Icon(_logs[i]['type'] == '비상 알림' ? Icons.warning_amber_rounded : Icons.check_circle_outline, 
                    color: _logs[i]['type'] == '비상 알림' ? Colors.red : Colors.green),
            title: Text(_logs[i]['type'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_logs[i]['msg']),
            trailing: Text(_logs[i]['time'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
      appBar: AppBar(title: const Text("설정"), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), 
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("실시간 감시 모드", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text("백그라운드에서 상시 감시", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      Switch(
                        value: _autoOn,
                        activeColor: const Color(0xFFFF8A65),
                        onChanged: (v) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setBool('auto_sms_enabled', v);
                          setState(() => _autoOn = v);
                          if (v) {
                            await FlutterForegroundTask.startService(notificationTitle: "안심 지키미 실행 중", notificationText: "실시간으로 사용자를 보호하고 있습니다.", callback: startCallback);
                          } else {
                            await FlutterForegroundTask.stopService();
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(onPressed: () async => await [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts].request(), 
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                        child: const Text("자동 권한 설정"))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: () => openAppSettings(), 
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        child: const Text("수동 설정"))),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Align(alignment: Alignment.centerLeft, child: Text("비상 연락처 관리", style: TextStyle(fontWeight: FontWeight.bold)))),
            ..._contacts.asMap().entries.map((entry) => ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFE0B2), child: Icon(Icons.person, color: Colors.orange)),
              title: Text(entry.value['name']),
              subtitle: Text(entry.value['number']),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent), onPressed: () async {
                setState(() => _contacts.removeAt(entry.key));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            )),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text("연락처 추가"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
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
          ],
        ),
      ),
    );
  }
}
