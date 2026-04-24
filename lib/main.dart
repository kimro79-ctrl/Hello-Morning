import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFEFF0F3),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.orangeAccent,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: '설정'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해 주세요";
    });
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);

    Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _isPressed = false;
          _lastCheckIn = now;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("하루 안부 지키미", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFCC80),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // 달력 위젯
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const Text("4월", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) => Text(["월","화","수","목","금","토","일"][i], style: const TextStyle(fontSize: 12, color: Colors.grey))),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) {
                    bool isToday = (i == 4); // 예시: 금요일 강조
                    return CircleAvatar(
                      radius: 15,
                      backgroundColor: isToday ? Colors.orangeAccent : Colors.transparent,
                      child: Text("${20 + i}", style: TextStyle(color: isToday ? Colors.white : Colors.black, fontSize: 13)),
                    );
                  }),
                )
              ],
            ),
          ),
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const Spacer(),
          // 입체 원형 스위치
          GestureDetector(
            onTap: _onCheckIn,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 210, height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEFF0F3),
                border: Border.all(
                  color: _isPressed ? Colors.redAccent : Colors.white, 
                  width: 10
                ),
                boxShadow: _isPressed ? [] : [
                  BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(10, 10), blurRadius: 18),
                  const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 18),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset('assets/smile.png', width: 150),
                  Positioned(bottom: 25, child: Text("CLICK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 2))),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Text("5분 미확인 시 자동 문자 발송", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 40),
        ],
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
  List<Map<String, String>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('contacts_list');
    if (data != null) {
      setState(() {
        _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i)));
      });
    }
  }

  void _addContact() async {
    if (_contacts.length >= 5) return;
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null && contact.phones!.isNotEmpty) {
        setState(() {
          _contacts.add({'name': contact.displayName ?? "보호자", 'number': contact.phones!.first.value ?? ""});
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('contacts_list', json.encode(_contacts));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 및 권한 설정"), backgroundColor: const Color(0xFFFFCC80)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("보호자 목록 (최대 5명)", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _contacts.length,
                itemBuilder: (context, i) => Card(
                  child: ListTile(
                    title: Text(_contacts[i]['name']!),
                    subtitle: Text(_contacts[i]['number']!),
                    trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () async {
                      setState(() => _contacts.removeAt(i));
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('contacts_list', json.encode(_contacts));
                    }),
                  ),
                ),
              ),
            ),
            ElevatedButton(onPressed: _addContact, child: const Text("연락처 추가")),
            const Divider(height: 40),
            const Text("수동 권한 승인"),
            const SizedBox(height: 10),
            _permBtn("1. 연락처 및 문자 권한 요청", () async {
              await [Permission.contacts, Permission.sms].request();
            }),
            const SizedBox(height: 10),
            _permBtn("2. 시스템 설정 (배터리 최적화 해제)", () => openAppSettings()),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _permBtn(String text, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(onPressed: onTap, child: Text(text)),
    );
  }
}
