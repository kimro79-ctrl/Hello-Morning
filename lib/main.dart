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

// ✅ 백그라운드 작업 핸들러 (이솔레이트 환경)
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp, TaskStarter starter) async {
    // ✅ 1. SharedPreferences 접근 안정화 (reload 추가)
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
          // ✅ 2. SMS 결과 확인 로직 추가 (삼성/샤오미 대응)
          SmsStatus result = await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심 지킴이] 응답 없음! 구글맵 확인:\nhttp://google.com/maps?q=${pos.latitude},${pos.longitude}"
          );
          
          debugPrint("SMS 발송 결과: $result");
          
          // 서비스 알림창에 전송 상태 표시
          FlutterForegroundTask.updateService(
            notificationTitle: '안심 지키미 알림',
            notificationText: result == SmsStatus.sent ? '긴급 문자 발송 완료' : '문자 발송 실패(권한 확인 필요)',
          );
        }

        String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        await p.setString('lastCheckIn', now);
      } catch (e) {
        debugPrint("백그라운드 에러: $e");
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, TaskStarter starter) async {}
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
      scaffoldBackgroundColor: const Color(0xFFFFFDF9),
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
        channelId: 'safety_service',
        channelName: '안심 지킴이 감시 서비스',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.HIGH, // 우선순위 상향
        iconData: const NotificationIconData(resType: ResourceType.mipmap, resPrefix: ResourcePrefix.ic, name: 'launcher'),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 180000, // 3분
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ✅ 3. 강력한 경고 문구로 수정된 권한 다이얼로그
  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("⚠️ 필수 설정 안내", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("삼성/샤오미 폰 사용자는 아래 설정을 안 하면\n위험 상황 시 문자가 절대 발송되지 않습니다.\n", style: TextStyle(fontSize: 13)),
            Divider(),
            Text("1. 위치: '항상 허용'\n2. 배터리: '제한 없음' 설정\n3. SMS/연락처 권한 승인", style: TextStyle(fontSize: 12, height: 1.8)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _startServiceWithPermissions(); },
            child: const Text("설정 및 서비스 시작"),
          )
        ],
      ),
    );
  }

  Future<void> _startServiceWithPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location, Permission.notification].request();
    await Permission.locationAlways.request();
    await Permission.ignoreBatteryOptimizations.request(); // 핵심 대책

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: '안심 지키미 작동 중',
        notificationText: '3분마다 안전을 확인하고 있습니다.',
        callback: startCallback,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: WithForegroundTask(child: IndexedStack(index: _currentIndex, children: _screens)),
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

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  int _selectedHours = 1;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkServiceStatus();
  }

  void _checkServiceStatus() async {
    bool running = await FlutterForegroundTask.isRunningService;
    setState(() => _isRunning = running);
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
            const SizedBox(height: 40),
            // ✅ 서비스 실행 상태 시각화
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _isRunning ? Colors.green : Colors.red),
                ),
                const SizedBox(width: 8),
                Text(_isRunning ? "지킴이 작동 중" : "지킴이 정지됨", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 20),
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
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
                child: const Icon(Icons.face_retouching_natural, size: 80, color: Colors.orangeAccent),
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
          // ✅ 시스템 설정 바로가기 배너 (강조)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.2))),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("삼성/샤오미 필수 체크", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const Text("앱 배터리 설정을 '제한 없음'으로 하셨나요?", style: TextStyle(fontSize: 11)),
                      const SizedBox(height: 4),
                      InkWell(onTap: () => openAppSettings(), child: const Text("지금 확인하기 >", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                )
              ],
            ),
          ),
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
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
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
