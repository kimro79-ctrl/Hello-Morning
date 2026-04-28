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
    [span_7](start_span)if (!(p.getBool('auto_sms_enabled') ?? false)) return;[span_7](end_span)

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    [span_8](start_span)if (last == null || contactsJson == null || contactsJson == "[]") return;[span_8](end_span)

    try {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
      int selectedHours = p.getInt('selectedHours') ?? [span_9](start_span)1;[span_9](end_span)
      int limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

      [span_10](start_span)if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {[span_10](end_span)
        // [로직 변경] 실내 최적화를 위해 SEND_SMS_ACTION 신호만 보냄
        sendPort?.send('SEND_SMS_ACTION');
      }
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  [span_11](start_span)runApp(const DailySafetyApp());[span_11](end_span)
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          [span_12](start_span)scaffoldBackgroundColor: const Color(0xFFF5F5DC),[span_12](end_span)
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
  [span_13](start_span)final List<Widget> _screens = [const HomeScreen(), const HistoryScreen(), const SettingScreen()];[span_13](end_span)
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _[span_14](start_span)initForegroundTask();[span_14](end_span)
    _bindReceivePort();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialSetup());
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

  // [핵심 수정] 좌표 포함 및 실내 최적화 발송 엔진
  Future<void> _executeEmergencySms() async {
    final p = await SharedPreferences.getInstance();
    
    // 중복 방지 (10분)
    String? lastSent = p.getString('lastEmergencySent');
    if (lastSent != null) {
      try {
        DateTime lastSentTime = DateTime.parse(lastSent);
        if (DateTime.now().difference(lastSentTime).inMinutes < 10) return;
      } catch (_) {}
    }

    String? contactsJson = p.getString('contacts_list');
    List contacts = [];
    try { contacts = json.decode(contactsJson ?? "[]"); } catch (_) {}
    if (contacts.isEmpty) return;

    // 실내 최적화 위치 정보 획득
    String locationStr = "좌표 확인 대기";
    try {
      Position pos = await Geolocator.getCurrentPosition(
        [span_15](start_span)desiredAccuracy: LocationAccuracy.balanced, // 실내용 GPS 하향[span_15](end_span)
        timeLimit: const Duration(seconds: 5),       // 5초 타임아웃
      );
      locationStr = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
    } catch (_) {
      Position? lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        locationStr = "${lastPos.latitude.toStringAsFixed(6)}, ${lastPos.longitude.toStringAsFixed(6)} (최근)";
      }
    }

    [span_16](start_span)List history = json.decode(p.getString('history_logs') ?? "[]");[span_16](end_span)

    for (var c in contacts) {
      if (c['number'] != null) {
        String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
        try {
          [span_17](start_span)// [요청 사항 반영] 좌표 포함 및 구글맵 안내 문구[span_17](end_span)
          SmsStatus status = await BackgroundSms.sendMessage(
            phoneNumber: cleanNumber,
            message: "[안심지키미] 응답이 없어 연락드립니다.\n좌표: $locationStr\n구글맵에서 좌표확인 부탁합니다.",
          );
          
          history.insert(0, {
            'type': status == SmsStatus.sent ? '비상 알림' : '발송 실패',
            'time': DateFormat('MM/dd HH:mm').format(DateTime.now()),
            'msg': '보호자(${c['name']}) 전송 결과: $status'
          });
        } catch (e) {
          history.insert(0, {'type': '에러', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': 'SMS 엔진 오류'});
        }
      }
    }

    [span_18](start_span)await p.setString('history_logs', json.encode(history.take(30).toList()));[span_18](end_span)
    await p.setString('lastEmergencySent', DateTime.now().toIso8601String());
    await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
    if (mounted) setState(() {});
  }

  Future<void> _initialSetup() async {
    await [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts, Permission.notification].request();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_v30',
        channelName: '안심 지키미 실시간 감시',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 60000, autoRunOnBoot: true, allowWakeLock: true),
    [span_19](start_span));[span_19](end_span)
  }

  @override
  Widget build(BuildContext context) => WithForegroundTask(
        child: Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            [span_20](start_span)selectedItemColor: const Color(0xFFFF8A65),[span_20](end_span)
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
              [span_21](start_span)BottomNavigationBarItem(icon: Icon(Icons.history_edu), label: '기록'),[span_21](end_span)
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '설정'),
            ],
          ),
        ),
      );
}

// --- 아래 UI 코드들은 제공해주신 파일의 디자인을 100% 따릅니다 ---

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  [span_22](start_span)State<HomeScreen> createState() => _HomeScreenState();[span_22](end_span)
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  [span_23](start_span)String _locationInfo = "위치 확인 중...";[span_23](end_span)
  [span_24](start_span)int _selectedHours = 1;[span_24](end_span)
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _[span_25](start_span)controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));[span_25](end_span)
    _[span_26](start_span)scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);[span_26](end_span)
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _[span_27](start_span)lastCheckIn = p.getString('lastCheckIn') ?? "안부를 전해주세요";[span_27](end_span)
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    try {
      [span_28](start_span)Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);[span_28](end_span)
      [span_29](start_span)if (mounted) setState(() => _locationInfo = "현재: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");[span_29](end_span)
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          [span_30](start_span)colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)],[span_30](end_span)
          stops: [0.0, 0.45],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            [span_31](start_span)const Text("안심 지키미", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),[span_31](end_span)
            const SizedBox(height: 5),
            Text(_locationInfo, style: const TextStyle(color: Color(0xFF78909C), fontSize: 12)),
            [span_32](start_span)const SizedBox(height: 35),[span_32](end_span)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [0, 1, 12, 24].map((h) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  [span_33](start_span)label: Text(h == 0 ? "5분" : "$h시간"),[span_33](end_span)
                  selected: _selectedHours == h,
                  onSelected: (v) async {
                    setState(() => _selectedHours = h);
                    (await SharedPreferences.getInstance()[span_34](start_span)).setInt('selectedHours', h);[span_34](end_span)
                  },
                ),
              )).toList(),
            ),
            const Spacer(flex: 2),
            [span_35](start_span)Text("마지막 체크인: $_lastCheckIn", style: const TextStyle(fontSize: 15, color: Colors.brown, fontWeight: FontWeight.w600)),[span_35](end_span)
            const SizedBox(height: 30),
            GestureDetector(
              [span_36](start_span)onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },[span_36](end_span)
              onTapUp: (_) async {
                setState(() => _isPressed = false); _controller.reverse();
                String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                [span_37](start_span)final p = await SharedPreferences.getInstance();[span_37](end_span)
                await p.setString('lastCheckIn', now);
                
                List history = json.decode(p.getString('history_logs') ?? "[]");
                history.insert(0, {'type': '활동 체크', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '본인 안부 확인 완료'});
                [span_38](start_span)await p.setString('history_logs', json.encode(history.take(30).toList()));[span_38](end_span)
                
                setState(() => _lastCheckIn = now);
                [span_39](start_span)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("체크 완료! 좋은 하루 되세요.")));[span_39](end_span)
              },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 210, height: 210,
                  decoration: BoxDecoration(
                    [span_40](start_span)shape: BoxShape.circle, color: Colors.white,[span_40](end_span)
                    boxShadow: [BoxShadow(color: _isPressed ? Colors.orangeAccent.withOpacity(0.5) : Colors.black12, blurRadius: 25)],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/smile.png', fit: BoxFit.cover, 
                      [span_41](start_span)errorBuilder: (c, e, s) => const Icon(Icons.face, size: 120, color: Colors.orange)),[span_41](end_span)
                  ),
                ),
              ),
            ),
            const Spacer(flex: 3),
            [span_42](start_span)const Text("미응답 시 설정된 연락처로 위치 정보가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 11)),[span_42](end_span)
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
  [span_43](start_span)State<HistoryScreen> createState() => _HistoryScreenState();[span_43](end_span)
}

class _HistoryScreenState extends State<HistoryScreen> {
  List _logs = [];
  @override
  void initState() { super.initState(); _load(); [span_44](start_span)}
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _logs = json.decode(p.getString('history_logs') ?? "[]"));[span_44](end_span)
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    [span_45](start_span)appBar: AppBar(title: const Text("활동 및 알림 기록"), backgroundColor: Colors.transparent),[span_45](end_span)
    body: _logs.isEmpty 
      ? const Center(child: Text("기록이 없습니다."))
      : ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, i) => ListTile(
            leading: Icon(_logs[i]['type'] == '비상 알림' ? Icons.warning_amber_rounded : Icons.check_circle_outline, 
                    [span_46](start_span)color: _logs[i]['type'] == '비상 알림' ? Colors.red : Colors.green),[span_46](end_span)
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
  [span_47](start_span)State<SettingScreen> createState() => _SettingScreenState();[span_47](end_span)
}

class _SettingScreenState extends State<SettingScreen> {
  List _contacts = [];
  bool _autoOn = false;
  @override
  void initState() { super.initState(); _load(); [span_48](start_span)}
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");[span_48](end_span)
      _autoOn = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      [span_49](start_span)appBar: AppBar(title: const Text("설정"), backgroundColor: Colors.transparent),[span_49](end_span)
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              [span_50](start_span)padding: const EdgeInsets.all(20),[span_50](end_span)
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), 
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        [span_51](start_span)children: [[span_51](end_span)
                          Text("실시간 감시 모드", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text("백그라운드에서 상시 감시", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      Switch(
                        value: _autoOn,
                        [span_52](start_span)activeColor: const Color(0xFFFF8A65),[span_52](end_span)
                        onChanged: (v) async {
                          final p = await SharedPreferences.getInstance();
                          [span_53](start_span)await p.setBool('auto_sms_enabled', v);[span_53](end_span)
                          setState(() => _autoOn = v);
                          if (v) {
                            await FlutterForegroundTask.startService(notificationTitle: "안심 지키미 실행 중", notificationText: "실시간으로 사용자를 보호하고 있습니다.", callback: startCallback);
                          } else {
                            [span_54](start_span)await FlutterForegroundTask.stopService();[span_54](end_span)
                          }
                        },
                      ),
                    ],
                  ),
                  [span_55](start_span)const Divider(height: 30),[span_55](end_span)
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(onPressed: () async => await [Permission.sms, Permission.location, Permission.contacts].request(), 
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                        [span_56](start_span)child: const Text("자동 권한 설정"))),[span_56](end_span)
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: () => openAppSettings(), 
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        [span_57](start_span)child: const Text("수동 설정"))),[span_57](end_span)
                    ],
                  ),
                ],
              ),
            ),
            [span_58](start_span)const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Align(alignment: Alignment.centerLeft, child: Text("비상 연락처 관리", style: TextStyle(fontWeight: FontWeight.bold)))),[span_58](end_span)
            ..._contacts.asMap().entries.map((entry) => ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFE0B2), child: Icon(Icons.person, color: Colors.orange)),
              title: Text(entry.value['name']),
              [span_59](start_span)subtitle: Text(entry.value['number']),[span_59](end_span)
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent), onPressed: () async {
                setState(() => _contacts.removeAt(entry.key));
                (await SharedPreferences.getInstance()[span_60](start_span)).setString('contacts_list', json.encode(_contacts));[span_60](end_span)
              }),
            )),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text("연락처 추가"),
                [span_61](start_span)style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),[span_61](end_span)
                onPressed: () async {
                  if (await Permission.contacts.request().isGranted) {
                    final c = await ContactsService.openDeviceContactPicker();
                    [span_62](start_span)if (c != null && c.phones!.isNotEmpty) {[span_62](end_span)
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
