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
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    int hrs = p.getInt('selectedHours') ?? 1;

    if (last == null || contactsJson == null || contactsJson == "[]") return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int limitMin = hrs == 0 ? 5 : hrs * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (_) {}

      String mapsUrl = pos != null 
          ? "http://maps.google.com/maps?q=${pos.latitude},${pos.longitude}" 
          : "위치확인불가";

      List contacts = json.decode(contactsJson);
      for (var c in contacts) {
        if (c['number'] == null) continue;
        String num = c['number'].toString().replaceAll(RegExp(r'[^0-9+]'), '');
        
        // ✅ 2, 4번: 결과 체크 및 로깅 강화
        var result = await BackgroundSms.sendMessage(
          phoneNumber: num,
          message: "[안심지키미] 응답지연 발생\n위치확인: $mapsUrl"
        );
        
        if (result != SmsStatus.sent) {
          debugPrint("⚠️ SMS 발송 실패: $result / 번호: $num");
        } else {
          debugPrint("✅ SMS 발송 성공 / 번호: $num");
        }
      }
      await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 1, 2번: 백그라운드 위치 권한 포함 필수 권한 요청
  Map<Permission, PermissionStatus> statuses = await [
    Permission.sms,
    Permission.contacts,
    Permission.location,
    Permission.notification,
  ].request();
  
  if (statuses[Permission.location]!.isGranted) {
    await Permission.locationAlways.request(); // 백그라운드 위치 필수
  }
  
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
  int _idx = 0;
  final List<Widget> _pages = [const HomeScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    _initTask();
  }

  void _initTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check',
        channelName: '안심지키미 서비스',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 300000,
        autoRunOnBoot: true,
        allowWakeLock: true, // ✅ 3번: CPU 휴면 방지
        allowWifiLock: true, // 네트워크 안정성 확보
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx, selectedFontSize: 10, unselectedFontSize: 10,
      onTap: (i) => setState(() => _idx = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 20), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 20), label: '설정'),
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
  String _last = "기록없음";
  int _hrs = 1;
  bool _down = false;

  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _last = p.getString('lastCheckIn') ?? "확인 버튼을 눌러주세요";
      _hrs = p.getInt('selectedHours') ?? 1;
    });
  }

  void _checkIn() async {
    final p = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await p.setString('lastCheckIn', now);
    setState(() => _last = now);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        const SizedBox(height: 15),
        const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 15),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "${h}h", style: const TextStyle(fontSize: 10)),
              selected: _hrs == h,
              onSelected: (v) async {
                setState(() => _hrs = h);
                (await SharedPreferences.getInstance()).setInt('selectedHours', h);
              },
            )).toList(),
          ),
        ),
        const Spacer(),
        Text("마지막 확인: $_last", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        const SizedBox(height: 15),
        GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) { setState(() => _down = false); _checkIn(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _down ? 135 : 145, height: _down ? 135 : 145,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: ClipOval(
              child: Image.asset(
                'assets/smile.png',
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.face_retouching_natural, size: 70, color: Colors.orangeAccent),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        const Text("매일 한 번 버튼을 눌러주세요", style: TextStyle(fontSize: 11, color: Colors.grey)),
        const Spacer(),
      ],
    ),
  );
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  List _list = [];
  bool _on = false;

  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _list = json.decode(p.getString('contacts_list') ?? "[]");
      _on = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Container(
          width: double.infinity, margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFE0B2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orangeAccent)),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 20, color: Colors.redAccent),
              const SizedBox(width: 10),
              const Expanded(child: Text("필수설정: 위치(항상허용), 배터리최적화 제외가 되어야 문자가 발송됩니다.", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              SizedBox(height: 28, child: ElevatedButton(onPressed: () => openAppSettings(), child: const Text("설정", style: TextStyle(fontSize: 10)))),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            title: const Text("자동 문자 기능 활성화", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: const Text("미응답 시 보호자에게 알림", style: TextStyle(fontSize: 10)),
            trailing: Transform.scale(
              scale: 1.3, // ✅ 스위치 크기만 확대
              child: Switch(
                value: _on,
                activeColor: Colors.orange,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('auto_sms_enabled', v);
                  setState(() => _on = v);
                  if (v) {
                    FlutterForegroundTask.startService(
                      notificationTitle: '안심지키미 실행 중',
                      notificationText: '보호 기능 작동 중',
                      callback: startCallback
                    );
                  } else {
                    FlutterForegroundTask.stopService();
                  }
                },
              ),
            ),
          ),
        ),
        const Divider(height: 20),
        Expanded(
          child: ListView.builder(
            itemCount: _list.length,
            itemBuilder: (c, i) => ListTile(
              dense: true,
              leading: const Icon(Icons.person, size: 18),
              title: Text(_list[i]['name'], style: const TextStyle(fontSize: 12)),
              subtitle: Text(_list[i]['number'], style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent), onPressed: () async {
                setState(() => _list.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_list));
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15),
          child: SizedBox(width: double.infinity, height: 42, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white),
            onPressed: () async {
              if (await Permission.contacts.request().isGranted) {
                final c = await ContactsService.openDeviceContactPicker();
                if (c != null) {
                  setState(() => _list.add({'name': c.displayName, 'number': c.phones?.first.value}));
                  (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_list));
                }
              }
            },
            child: const Text("보호자 등록", style: TextStyle(fontSize: 12)),
          )),
        ),
      ],
    ),
  );
}
