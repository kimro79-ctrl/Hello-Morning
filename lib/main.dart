import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:direct_sms/direct_sms.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

// 1. 배경 작업: 5분 미확인 시 자동 문자 발송
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckInStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts_list');

    if (lastCheckInStr != null && contactJson != null) {
      DateTime lastCheck = DateFormat('yyyy-MM-dd HH:mm').parse(lastCheckInStr);
      int diff = DateTime.now().difference(lastCheck).inMinutes;

      if (diff >= 5) { // 테스트용 5분 설정
        List<dynamic> contacts = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        for (var c in contacts) {
          try {
            await directSms.sendSms(
              message: "[하루 안부] 5분간 안부 미확인으로 자동 발송되었습니다.",
              phone: c['number'],
            );
          } catch (e) {
            debugPrint("발송 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    "safety_task_5min",
    "periodicCheck",
    frequency: const Duration(minutes: 15), // 안드로이드 최소 주기
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
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
        backgroundColor: Colors.white,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: '연락처'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_suggest_rounded), label: '권한설정'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// [홈 화면] 사진의 텍스트/달력/버튼 디자인 완벽 구현
// ---------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록이 없습니다";
  bool _isPressed = false;
  List<String> _checkedDates = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    // 포그라운드에서도 30초마다 체크 실행
    Timer.periodic(const Duration(seconds: 30), (t) => _loadData());
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "버튼을 눌러주세요";
      _checkedDates = prefs.getStringList('checkedDates') ?? [];
    });
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    DateTime now = DateTime.now();
    String timeStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
    String dateStr = DateFormat('yyyy-MM-dd').format(now);

    if (!_checkedDates.contains(dateStr)) _checkedDates.add(dateStr);
    await prefs.setString('lastCheckIn', timeStr);
    await prefs.setStringList('checkedDates', _checkedDates);

    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = timeStr; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF0F3),
      appBar: AppBar(
        title: const Text("하루 안부", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 20)),
        backgroundColor: const Color(0xFFFFCC80),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 30),
          _buildWeeklyCalendar(), // 주간 달력 섹션
          const Spacer(),
          // 텍스트 디테일: 사진처럼 회색 소제목 + 굵은 본문
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 13, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87)),
          const SizedBox(height: 40),
          
          // 입체형 원형 버튼 (사각형 없음)
          GestureDetector(
            onTap: _onCheckIn,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 230, height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEFF0F3),
                border: Border.all(color: _isPressed ? Colors.redAccent : Colors.white, width: 8),
                boxShadow: _isPressed ? [] : [
                  BoxShadow(color: Colors.black.withOpacity(0.12), offset: const Offset(12, 12), blurRadius: 24),
                  const BoxShadow(color: Colors.white, offset: Offset(-12, -12), blurRadius: 24),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset('assets/smile.png', width: 170),
                  // 사진 속 CLICK 텍스트 재현
                  Positioned(
                    bottom: 35,
                    child: Text(
                      "CLICK",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: _isPressed ? Colors.redAccent.withOpacity(0.6) : Colors.black12,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 30),
            child: Text("5분 미확인 시 자동 발송 모드", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyCalendar() {
    DateTime now = DateTime.now();
    DateTime monday = now.subtract(Duration(days: now.weekday - 1));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 25),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Text(DateFormat('M월').format(now), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (i) {
              DateTime day = monday.add(Duration(days: i));
              String dateStr = DateFormat('yyyy-MM-dd').format(day);
              bool isChecked = _checkedDates.contains(dateStr);
              bool isToday = dateStr == DateFormat('yyyy-MM-dd').format(now);
              return Column(
                children: [
                  Text(["월","화","수","목","금","토","일"][i], style: TextStyle(fontSize: 11, color: isToday ? Colors.orange : Colors.grey[400], fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(height: 6),
                  Text(DateFormat('d').format(day), style: TextStyle(fontSize: 13, fontWeight: isToday ? FontWeight.w900 : FontWeight.w500, color: isToday ? Colors.orange : Colors.black54)),
                  const SizedBox(height: 8),
                  isChecked 
                    ? const Icon(Icons.check_circle, color: Colors.orangeAccent, size: 26)
                    : Icon(Icons.radio_button_unchecked, color: Colors.grey[100], size: 26),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// [연락처 화면] 보호자 5명 제한
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(title: const Text("보호자 연락처 (최대 5명)"), backgroundColor: const Color(0xFFFFCC80)),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _contacts.length,
        itemBuilder: (context, i) => Card(
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            title: Text(_contacts[i]['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_contacts[i]['number']!),
            trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () async {
              setState(() => _contacts.removeAt(i));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('contacts_list', json.encode(_contacts));
            }),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orangeAccent,
        onPressed: () async {
          if (_contacts.length >= 5) return;
          if (await Permission.contacts.request().isGranted) {
            final c = await ContactsService.openDeviceContactPicker();
            if (c != null) {
              setState(() => _contacts.add({'name': c.displayName!, 'number': c.phones!.first.value!}));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('contacts_list', json.encode(_contacts));
            }
          }
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

// ---------------------------------------------------------
// [권한 설정 화면]
// ---------------------------------------------------------
class SettingScreen extends StatelessWidget {
  const SettingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("권한 설정"), backgroundColor: const Color(0xFFFFCC80)),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            const ListTile(leading: Icon(Icons.info_outline), title: Text("자동 문자 발송을 위해 SMS 및 연락처 권한이 필요합니다.")),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey, minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: () => openAppSettings(),
              child: const Text("시스템 설정 열기 (배터리 최적화 해제)", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
