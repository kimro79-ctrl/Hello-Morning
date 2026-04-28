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
void startCallback() => FlutterForegroundTask.setTaskHandler(MyTaskHandler());

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
        pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 8));
      } catch (_) {}

      String mapsUrl = pos != null 
          ? "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}" 
          : "위치정보 확인불가";

      List contacts = json.decode(contactsJson);
      for (var c in contacts) {
        String num = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
        await BackgroundSms.sendMessage(
          phoneNumber: num,
          message: "[안심지키미] 장시간 응답 없음\n현위치: $mapsUrl"
        );
      }
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
  final List<Widget> _pages = [const HomeScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    _initTask();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDetailNotice());
  }

  void _initTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety', channelName: '안심지키미', 
        channelImportance: NotificationChannelImportance.LOW, priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(interval: 180000, autoRunOnBoot: true),
    );
  }

  // ✅ 자세한 팝업 공지 기능
  void _showDetailNotice() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.security, color: Colors.orange), SizedBox(width: 8), Text("서비스 이용 안내", style: TextStyle(fontSize: 16))]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("1. 작동 원리", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text("설정한 시간 동안 앱 내 버튼을 누르지 않으면, 등록된 보호자에게 위치가 포함된 문자가 자동 발송됩니다.", style: TextStyle(fontSize: 12)),
            SizedBox(height: 10),
            Text("2. 필수 권한 설정 (중요)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.redAccent)),
            Text("• 위치: 반드시 '항상 허용' 선택\n• SMS: 문자 발송 권한 허용\n• 배터리: '제한 없음' 또는 '최적화 제외'", style: TextStyle(fontSize: 12)),
            SizedBox(height: 10),
            Text("3. 주의 사항", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text("휴대폰이 꺼져있거나 네트워크 연결이 끊기면 작동하지 않을 수 있습니다.", style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _reqPerms(); }, child: const Text("확인 및 권한설정"))
        ],
      ),
    );
  }

  Future<void> _reqPerms() async {
    await [Permission.sms, Permission.contacts, Permission.location, Permission.notification].request();
    if (await Permission.location.isGranted) await Permission.locationAlways.request();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx, selectedFontSize: 10, unselectedFontSize: 10,
      onTap: (i) => setState(() => _idx = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home, size: 18), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 18), label: '설정'),
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
        const SizedBox(height: 20),
        const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 20),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 45),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "${h}시간", style: const TextStyle(fontSize: 10)),
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, 
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: _down ? 5 : 12)]),
            child: const Icon(Icons.face_retouching_natural, size: 65, color: Colors.orangeAccent),
          ),
        ),
        const SizedBox(height: 15),
        const Text("매일 한 번 버튼을 눌러주세요", style: TextStyle(fontSize: 11, color: Colors.grey)), // ✅ 요청 문구 수정
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
          width: double.infinity, margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFE0B2), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(child: Text("발송 오류 방지: 위치(항상허용), 배터리최적화 제외 필수", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              GestureDetector(onTap: () => openAppSettings(), child: const Text("설정가기", style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        SwitchListTile(
          dense: true, title: const Text("자동 문자 기능 활성화", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          value: _on, activeColor: Colors.orange,
          onChanged: (v) async {
            final p = await SharedPreferences.getInstance();
            await p.setBool('auto_sms_enabled', v);
            setState(() => _on = v);
            if (v) {
              FlutterForegroundTask.startService(notificationTitle: '안심지키미 실행 중', notificationText: '당신의 안전을 체크하고 있습니다.', callback: startCallback);
            } else {
              FlutterForegroundTask.stopService();
            }
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _list.length,
            itemBuilder: (c, i) => ListTile(
              dense: true, title: Text(_list[i]['name'], style: const TextStyle(fontSize: 12)),
              subtitle: Text(_list[i]['number'], style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, size: 16), onPressed: () async {
                setState(() => _list.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_list));
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
          child: SizedBox(width: double.infinity, height: 42, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              if (await Permission.contacts.request().isGranted) {
                final c = await ContactsService.openDeviceContactPicker();
                if (c != null) {
                  setState(() => _list.add({'name': c.displayName, 'number': c.phones?.first.value}));
                  (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_list));
                }
              }
            },
            child: const Text("보호자 등록", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          )),
        ),
      ],
    ),
  );
}
