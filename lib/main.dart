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
            bodyLarge: TextStyle(fontSize: 14),
            bodyMedium: TextStyle(fontSize: 13),
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
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey();
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
      _checkAndShowNotice();
    });
  }

  Future<void> _checkAndShowNotice() async {
    final p = await SharedPreferences.getInstance();
    String? lastHideDate = p.getString('hide_notice_date');
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (lastHideDate != today) {
      _showNoticeDialog();
    }
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
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, 
        timeLimit: const Duration(seconds: 4),
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
          await BackgroundSms.sendMessage(phoneNumber: cleanNumber, message: "[안심지키미] 응답이 없어 연락드립니다.\n좌표: $locationStr\n구글맵에서 좌표확인 부탁합니다.");
          history.insert(0, {'type': '비상 알림', 'time': DateFormat('MM/dd HH:mm').format(DateTime.now()), 'msg': '보호자(${c['name']})에게 안심 문자 재발송 완료'});
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

  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("🚨 중요 작동 가이드", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("정상적인 안심 문자 발송을 위해 필수 확인이 필요합니다.", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              Divider(height: 20),
              Text("1. 위치 권한 상시 허용", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("위치 권한을 '항상 허용'으로 설정해야 백그라운드에서 감지가 가능합니다.", style: TextStyle(fontSize: 11)),
              SizedBox(height: 10),
              Text("2. 배터리 최적화 제외", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("휴대폰 설정에서 본 앱을 '배터리 제한 없음' 등록해야 서비스가 죽지 않습니다.", style: TextStyle(fontSize: 11)),
              SizedBox(height: 10),
              Text("3. 앱 종료 금지 (중요)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              Text("최근 앱 목록에서 완전히 종료하면 문자가 발송되지 않습니다. 앱은 홈 버튼으로 실행 상태를 유지해 주세요.", style: TextStyle(fontSize: 11, color: Colors.redAccent)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
              await p.setString('hide_notice_date', today);
              Navigator.pop(context);
            },
            child: const Text("오늘 하루 보지 않기", style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_v36', 
        channelName: '안심 지키미 서비스', 
        channelImportance: NotificationChannelImportance.MAX, 
        priority: NotificationPriority.HIGH
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 30000, 
        autoRunOnBoot: true, 
        allowWakeLock: true 
      ),
    );
  }

  @override
  Widget build(BuildContext context) => WithForegroundTask(
        child: Scaffold(
          body: IndexedStack(index: _currentIndex, children: _screens),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: const Color(0xFFFF8A65),
            selectedFontSize: 11,
            unselectedFontSize: 11,
            onTap: (index) {
              setState(() => _currentIndex = index);
              if (index == 1) {
                _historyKey.currentState?.loadLogs();
              }
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
  String _lastCheckIn = "오늘 하루 안부를 전해주세요"; 
  String _locationInfo = "위치 확인 중...";
  int _selectedHours = 1;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 하루 안부를 전해주세요"; 
        _selectedHours = p.getInt('selectedHours') ?? 1;
      });
      _updateLocation();
    }
  }

  Future<void> _updateLocation() async {
    Position? lastPos = await Geolocator.getLastKnownPosition();
    if (lastPos != null && mounted) {
      setState(() => _locationInfo = "최근 위치: ${lastPos.latitude.toStringAsFixed(4)}, ${lastPos.longitude.toStringAsFixed(4)}");
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, 
        timeLimit: const Duration(seconds: 4),
      );
      if (mounted) setState(() => _locationInfo = "현재 위치: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)], stops: [0.0, 0.45]),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
            const SizedBox(height: 5),
            Text(_locationInfo, style: const TextStyle(color: Color(0xFF78909C), fontSize: 11)),
            const SizedBox(height: 35),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [0, 1, 12, 24].map((h) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 11)),
                  selected: _selectedHours == h,
                  onSelected: (v) async {
                    setState(() => _selectedHours = h);
                    (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                  },
                ),
              )).toList(),
            ),
            const Spacer(flex: 2),
            Text("마지막 체크인: $_lastCheckIn", style: const TextStyle(fontSize: 14, color: Colors.brown, fontWeight: FontWeight.w600)),
            const SizedBox(height: 30),
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("체크 완료! 좋은 하루 되세요.", style: TextStyle(fontSize: 12))));
              },
              onTapCancel: () { setState(() => _isPressed = false); _controller.reverse(); },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF5F5DC),
                    boxShadow: _isPressed 
                      ? [
                          BoxShadow(color: const Color(0xFFFFD1DC).withOpacity(0.8), blurRadius: 20, spreadRadius: 5),
                          BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(2, 2), blurRadius: 5),
                        ]
                      : [
                          BoxShadow(color: Colors.black.withOpacity(0.12), offset: const Offset(8, 8), blurRadius: 15),
                          BoxShadow(color: Colors.white, offset: const Offset(-8, -8), blurRadius: 15),
                        ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: _isPressed ? const Color(0xFFFFD1DC) : const Color(0xFFFFD1DC).withOpacity(0.3), 
                          width: _isPressed ? 4 : 2
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/smile.png', 
                          fit: BoxFit.cover, 
                          errorBuilder: (c, e, s) => const Icon(Icons.face, size: 120, color: Colors.orange)
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(flex: 3),
            const Text("미응답 시 설정된 연락처로 위치 정보가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 10)),
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
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List _logs = [];
  @override
  void initState() { super.initState(); loadLogs(); }

  Future<void> loadLogs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _logs = json.decode(p.getString('history_logs') ?? "[]");
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("활동 및 알림 기록", style: TextStyle(fontSize: 18)), backgroundColor: Colors.transparent),
    body: _logs.isEmpty 
      ? const Center(child: Text("기록이 없습니다.", style: TextStyle(fontSize: 13)))
      : ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, i) => ListTile(
            leading: Icon(_logs[i]['type'] == '비상 알림' ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: _logs[i]['type'] == '비상 알림' ? Colors.red : Colors.green, size: 20),
            title: Text(_logs[i]['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(_logs[i]['msg'], style: const TextStyle(fontSize: 11)),
            trailing: Text(_logs[i]['time'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        ),
  );
}

class NeumorphicSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const NeumorphicSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 65, height: 35, padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? const Color(0xFFFF8A65) : const Color(0xFFE0E0E0),
          boxShadow: [
            if (!value) BoxShadow(color: Colors.white, offset: const Offset(-2, -2), blurRadius: 3, spreadRadius: 1),
            if (!value) BoxShadow(color: Colors.grey.withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 3, spreadRadius: 1),
            if (value) BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(1, 1), blurRadius: 2),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 27, height: 27,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), offset: const Offset(0, 1), blurRadius: 2)],
            ),
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
  bool _autoOn = false;
  @override
  void initState() { super.initState(); _load(); }
  
  void _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _contacts = json.decode(p.getString('contacts_list') ?? "[]");
        _autoOn = p.getBool('auto_sms_enabled') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontSize: 18)), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(20), 
                border: Border.all(color: _autoOn ? const Color(0xFFFFD1DC) : Colors.transparent, width: 2.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("실시간 감시 모드", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)), Text("백그라운드에서 상시 감시", style: TextStyle(fontSize: 10, color: Colors.grey))]),
                      NeumorphicSwitch(
                        value: _autoOn,
                        onChanged: (v) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setBool('auto_sms_enabled', v);
                          setState(() => _autoOn = v);
                          if (v) {
                            await FlutterForegroundTask.startService(notificationTitle: "1인가구 안심 지키미 실행 중", notificationText: "실시간으로 사용자를 보호하고 있습니다.", callback: startCallback);
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
                      Expanded(child: ElevatedButton(onPressed: () async => await [Permission.sms, Permission.location, Permission.locationAlways, Permission.contacts].request(), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)), child: const Text("자동 권한 설정", style: TextStyle(fontSize: 11)))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: () => openAppSettings(), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 10)), child: const Text("수동 설정", style: TextStyle(fontSize: 11)))),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Align(alignment: Alignment.centerLeft, child: Text("비상 연락처 관리", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
            ..._contacts.asMap().entries.map((entry) => ListTile(
              leading: const CircleAvatar(radius: 18, backgroundColor: Color(0xFFFFE0B2), child: Icon(Icons.person, color: Colors.orange, size: 18)),
              title: Text(entry.value['name'], style: const TextStyle(fontSize: 13)),
              subtitle: Text(entry.value['number'], style: const TextStyle(fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20), onPressed: () async {
                setState(() => _contacts.removeAt(entry.key));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            )),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text("연락처 추가", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
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
