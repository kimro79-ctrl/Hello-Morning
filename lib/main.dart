import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:direct_sms/direct_sms.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

// 배경 작업 (5분 체크)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await checkAndSendSms();
    return Future.value(true);
  });
}

Future<void> checkAndSendSms() async {
  final prefs = await SharedPreferences.getInstance();
  final lastCheckInStr = prefs.getString('lastCheckIn');
  final contactJson = prefs.getString('contacts_list');
  const int timeoutLimit = 5; // 테스트용 5분

  if (lastCheckInStr != null && contactJson != null) {
    DateTime lastCheck = DateFormat('yyyy-MM-dd HH:mm').parse(lastCheckInStr);
    int diff = DateTime.now().difference(lastCheck).inMinutes;
    if (diff >= timeoutLimit) {
      List<dynamic> contacts = json.decode(contactJson);
      final DirectSms directSms = DirectSms();
      for (var c in contacts) {
        try {
          await directSms.sendSms(message: "[하루 안부 테스트] 5분간 미확인되었습니다.", phone: c['number']);
        } catch (e) { debugPrint(e.toString()); }
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask("1", "periodicSafetyCheck", frequency: const Duration(minutes: 15));
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MainNavigation()));
}

// [네비게이션 제어] - 페이지 분리 핵심
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const ContactScreen(), const LogScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex], // 선택된 인덱스에 따라 페이지 전환
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.orangeAccent,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: '보호자'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_rounded), label: '기록'),
        ],
      ),
    );
  }
}

// [페이지 1] 홈 화면
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "안부를 확인해주세요";
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _load();
    Timer.periodic(const Duration(seconds: 30), (t) { checkAndSendSms(); _load(); });
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _lastCheckIn = prefs.getString('lastCheckIn') ?? "확인 버튼을 눌러주세요");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFFFCC80), centerTitle: true, elevation: 0),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("마지막 확인", style: TextStyle(color: Colors.grey)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
          const SizedBox(height: 50),
          Center(
            child: GestureDetector(
              onTap: () async {
                setState(() => _isPressed = true);
                final prefs = await SharedPreferences.getInstance();
                String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                await prefs.setString('lastCheckIn', now);
                List<String> logs = prefs.getStringList('safety_logs') ?? [];
                logs.insert(0, now);
                await prefs.setStringList('safety_logs', logs);
                Timer(const Duration(milliseconds: 600), () => setState(() { _isPressed = false; _lastCheckIn = now; }));
              },
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: _isPressed ? Colors.redAccent : Colors.white, width: 8), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
                child: Center(child: Image.asset('assets/smile.png', width: 150)),
              ),
            ),
          ),
          const SizedBox(height: 50),
          const Text("5분 미확인 시 자동 발송 (테스트)", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      ),
    );
  }
}

// [페이지 2] 보호자 화면 (Card UI)
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});
  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  List<Map<String, String>> _contacts = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('contacts_list');
    if (data != null) setState(() => _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("비상 연락망"), backgroundColor: const Color(0xFFFFCC80)),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _contacts.length,
        itemBuilder: (context, i) => Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(title: Text(_contacts[i]['name']!), subtitle: Text(_contacts[i]['number']!), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
            setState(() => _contacts.removeAt(i));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('contacts_list', json.encode(_contacts));
          })),
        ),
      ),
      floatingActionButton: FloatingActionButton(backgroundColor: Colors.orangeAccent, onPressed: () async {
        if (await Permission.contacts.request().isGranted) {
          final c = await ContactsService.openDeviceContactPicker();
          if (c != null) {
            setState(() => _contacts.add({'name': c.displayName!, 'number': c.phones!.first.value!}));
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('contacts_list', json.encode(_contacts));
          }
        }
      }, child: const Icon(Icons.person_add)),
    );
  }
}

// [페이지 3] 기록 화면 (로그 리스트)
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<String> _logs = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _logs = prefs.getStringList('safety_logs') ?? []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("안부 기록"), backgroundColor: const Color(0xFFFFCC80)),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _logs.length,
        itemBuilder: (context, i) => ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(_logs[i])),
      ),
    );
  }
}
