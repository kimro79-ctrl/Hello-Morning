import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sms_plus/flutter_sms_plus.dart'; 
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
            bodyLarge: TextStyle(fontSize: 12),
            bodyMedium: TextStyle(fontSize: 11),
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
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey<HistoryScreenState>();
  late List<Widget> _screens;
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _screens = [const HomeScreen(), HistoryScreen(key: _historyKey), const SettingScreen()];
    _initForegroundTask();
    _bindReceivePort();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
      _showGuideDialog(); 
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
          // 수정된 SMS 발송 라이브러리 사용
          await FlutterSmsPlus().sendSms(
            to: cleanNumber,
            message: "[1인가구 안심 지키미] 응답이 없어 연락드립니다.\n좌표: $locationStr\n확인 부탁드립니다."
          );
          history.insert(0, {'type': '비상 알림', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '보호자(${c['name']})에게 안심 문자 발송 완료'});
        } catch (e) {
          history.insert(0, {'type': '에러', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': 'SMS 전송 실패'});
        }
      }
    }
    await p.setString('history_logs', json.encode(history.take(30).toList()));
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());
    _historyKey.currentState?.loadLogs();
    if (mounted) setState(() {});
  }

  Future<void> _initialSetup() async {
    await [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts, Permission.notification].request();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🏠 안심 지키미 안내", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("⚠️ 필수 확인", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12)),
              SizedBox(height: 5),
              Text("• 어플 종료 시 문자 발송 안됩니다.", style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
              Text("• 안전감시모드 스위치 껏다 다시켜주세요.", style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
              Divider(height: 20),
              Text("📍 위치 권한: '항상 허용'", style: TextStyle(fontSize: 11)),
              Text("💬 SMS 권한: [자동 권한설정] 승인", style: TextStyle(fontSize: 11)),
              Text("🔋 배터리 최적화: '제한 없음'", style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인했습니다", style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_v38', 
        channelName: '1인가구 안심 지키미', 
        channelImportance: NotificationChannelImportance.MAX, 
        priority: NotificationPriority.HIGH
      ),
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
            selectedFontSize: 10,
            unselectedFontSize: 10,
            onTap: (index) {
              setState(() => _currentIndex = index);
              if (index == 1) _historyKey.currentState?.loadLogs();
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 22), label: '홈'),
              BottomNavigationBarItem(icon: Icon(Icons.history_edu, size: 22), label: '기록'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined, size: 22), label: '설정'),
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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _lastCheckIn = "안부를 전해주세요";
  String _locationInfo = "위치 확인 중...";
  int _selectedHours = 1;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
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
      if (mounted) setState(() => _locationInfo = "현재 위치: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)],
          stops: [0.0, 0.4],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
            const SizedBox(height: 5),
            Text(_locationInfo, style: const TextStyle(color: Color(0xFF78909C), fontSize: 10)),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [0, 1, 12, 24].map((h) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 10)),
                  selected: _selectedHours == h,
                  onSelected: (v) async {
                    setState(() => _selectedHours = h);
                    (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                  },
                ),
              )).toList(),
            ),
            const Spacer(flex: 2),
            Text("마지막 체크인: $_lastCheckIn", style: const TextStyle(fontSize: 12, color: Colors.brown, fontWeight: FontWeight.w600)),
            const SizedBox(height: 25),
            GestureDetector(
              onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
              onTapUp: (_) async {
                setState(() => _isPressed = false); _controller.reverse();
                String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                final p = await SharedPreferences.getInstance();
                await p.setString('lastCheckIn', now);
                await p.remove('lastEmergencySent');
                List history = json.decode(p.getString('history_logs') ?? "[]");
                history.insert(0, {'type': '활동 체크', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 안부 확인 완료'});
                await p.setString('history_logs', json.encode(history.take(30).toList()));
                setState(() => _lastCheckIn = now);
              },
              onTapCancel: () { setState(() => _isPressed = false); _controller.reverse(); },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 190, height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: Colors.white, 
                    border: _isPressed ? Border.all(color: const Color(0xFFFFD1DC), width: 6) : null,
                    boxShadow: _isPressed 
                        ? [BoxShadow(color: const Color(0xFFFFD1DC).withOpacity(0.8), blurRadius: 15, spreadRadius: 3)]
                        : [const BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(3, 3))],
                  ),
                  child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.face, size: 90, color: Colors.orange))),
                ),
              ),
            ),
            const Spacer(flex: 3),
            const Text("미응답 시 설정된 연락처로 위치 정보가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 9)),
            const SizedBox(height: 20),
          ],
        ),
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
  @override
  void initState() { super.initState(); loadLogs(); }
  Future<void> loadLogs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _logs = json.decode(p.getString('history_logs') ?? "[]"));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("안심 활동 기록", style: TextStyle(fontSize: 15)), backgroundColor: Colors.transparent),
    body: _logs.isEmpty 
      ? const Center(child: Text("기록이 없습니다.", style: TextStyle(fontSize: 11)))
      : ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, i) => ListTile(
            leading: Icon(_logs[i]['type'] == '비상 알림' ? 
              Icons.warning_amber_rounded : Icons.check_circle_outline, color: _logs[i]['type'] == '비상 알림' ? Colors.red : Colors.green, size: 18),
            title: Text(_logs[i]['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            subtitle: Text(_logs[i]['msg'], style: const TextStyle(fontSize: 10)),
            trailing: Text(_logs[i]['time'], style: const TextStyle(fontSize: 9, color: Colors.grey)),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정 및 가이드", style: TextStyle(fontSize: 15)), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("안심 감시 모드", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), Text("백그라운드에서 상시 작동", style: TextStyle(fontSize: 9, color: Colors.grey))]),
                      Switch(
                        value: _autoOn,
                        activeColor: const Color(0xFFFF8A65),
                        onChanged: (v) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setBool('auto_sms_enabled', v);
                          setState(() => _autoOn = v);
                          if (v) {
                            await FlutterForegroundTask.startService(notificationTitle: "1인가구 안심 지키미 작동 중", notificationText: "실시간 감시가 활성화되었습니다.", callback: startCallback);
                          } else {
                            await FlutterForegroundTask.stopService();
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(
                        onPressed: () async { await [Permission.sms, Permission.location, Permission.locationAlways].request(); }, 
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), minimumSize: const Size(0, 38)), 
                        child: const Text("자동 권한설정", style: TextStyle(fontSize: 11))
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: () => openAppSettings(), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), minimumSize: const Size(0, 38)), child: const Text("기타 수동 설정", style: TextStyle(fontSize: 11)))),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Align(alignment: Alignment.centerLeft, child: Text("비상 연락처 관리", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
            ..._contacts.asMap().entries.map((entry) => ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFE0B2), radius: 16, child: Icon(Icons.person, color: Colors.orange, size: 18)),
              title: Text(entry.value['name'], style: const TextStyle(fontSize: 12)),
              subtitle: Text(entry.value['number'], style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18), onPressed: () async {
                setState(() => _contacts.removeAt(entry.key));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            )),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text("보호자 연락처 추가", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  if (await FlutterContacts.requestPermission()) {
                    final contact = await FlutterContacts.openExternalPick();
                    if (contact != null && contact.phones.isNotEmpty) {
                      setState(() => _contacts.add({
                        'name': contact.displayName, 
                        'number': contact.phones.first.number
                      }));
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
