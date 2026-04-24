import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:direct_sms/direct_sms.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckInStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts_list');
    if (lastCheckInStr != null && contactJson != null) {
      DateTime lastCheck = DateFormat('yyyy-MM-dd HH:mm').parse(lastCheckInStr);
      if (DateTime.now().difference(lastCheck).inMinutes >= 5) { // 테스트 5분
        List<dynamic> contacts = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        for (var c in contacts) {
          try { await directSms.sendSms(message: "[안부 지킴이] 5분간 응답이 없어 발송되었습니다.", phone: c['number']); } catch (e) {}
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MainNavigation()));
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const ContactScreen(), const SettingScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.orangeAccent,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: '보호자'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: '설정'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// [1] 홈 화면: 주간 달력 + 메인 버튼 (레드 테두리 효과)
// ---------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  bool _isPressed = false;

  @override
  void initState() { super.initState(); _loadData(); }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요");
  }

  void _onPressButton() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    // 0.5초 후 레드 테두리 해제
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = now; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(title: const Text("하루 안부", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), 
      backgroundColor: const Color(0xFFFFE0B2), centerTitle: true, elevation: 0),
      body: Column(
        children: [
          const SizedBox(height: 20),
          _buildWeeklyCalendar(), // 컨셉 이미지 기반 달력
          const Spacer(),
          GestureDetector(
            onTap: _onPressButton,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 240, height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,
                border: Border.all(color: _isPressed ? Colors.red : Colors.white, width: 10),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10))],
              ),
              child: Center(child: Image.asset('assets/smile.png', width: 160)),
            ),
          ),
          const SizedBox(height: 20),
          Text("마지막 확인: $_lastCheckIn", style: const TextStyle(color: Colors.grey)),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildWeeklyCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(
        children: [
          const Text("1월", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ["금", "토", "일", "월", "화", "수", "목"].map((day) => Column(
              children: [
                Text(day, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                const Icon(Icons.check_circle, color: Colors.orangeAccent, size: 28),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// [2] 보호자 화면: 5개 등록 제한 + 카드 UI
// ---------------------------------------------------------
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

  void _add() async {
    if (_contacts.length >= 5) return;
    if (await Permission.contacts.request().isGranted) {
      final c = await ContactsService.openDeviceContactPicker();
      if (c != null) {
        setState(() => _contacts.add({'name': c.displayName!, 'number': c.phones!.first.value!}));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('contacts_list', json.encode(_contacts));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("비상 연락망"), backgroundColor: const Color(0xFFFFE0B2)),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _contacts.length,
        itemBuilder: (context, i) => Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            title: Text(_contacts[i]['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_contacts[i]['number']!),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {
              setState(() => _contacts.removeAt(i));
              SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
            }),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, backgroundColor: Colors.orangeAccent, child: const Icon(Icons.person_add)),
    );
  }
}

// ---------------------------------------------------------
// [3] 설정 화면: 연락처 & 문자 권한 수동 설정
// ---------------------------------------------------------
class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _smsOk = false;
  bool _contactOk = false;

  @override
  void initState() { super.initState(); _check(); }

  void _check() async {
    _smsOk = await Permission.sms.isGranted;
    _contactOk = await Permission.contacts.isGranted;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정 및 권한"), backgroundColor: const Color(0xFFFFE0B2)),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildAuthTile("연락처 권한", _contactOk, Permission.contacts),
            _buildAuthTile("문자 발송 권한", _smsOk, Permission.sms),
            const Divider(height: 40),
            ElevatedButton(
              onPressed: () => openAppSettings(),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, minimumSize: const Size(double.infinity, 50)),
              child: const Text("시스템 설정 열기 (배터리 최적화 해제 등)", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthTile(String title, bool isOk, Permission p) {
    return ListTile(
      title: Text(title),
      trailing: isOk ? const Icon(Icons.check_circle, color: Colors.green) : const Text("허용 필요", style: TextStyle(color: Colors.red)),
      onTap: () async { await p.request(); _check(); },
    );
  }
}
