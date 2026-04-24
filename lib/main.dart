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

// 상단 타이틀용 그라데이션 위젯
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.gradient, this.style});
  final String text;
  final Gradient gradient;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(text, style: style),
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
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // 1분마다 자동 체크
    _autoCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) => _checkAutoSms());
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해 주세요";
    });
  }

  Future<void> _checkAutoSms() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastTimeStr = prefs.getString('lastCheckIn');
    String? contactsJson = prefs.getString('contacts_list');
    
    if (lastTimeStr != null && contactsJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      if (DateTime.now().difference(lastTime).inMinutes >= 5) {
        List<dynamic> contacts = json.decode(contactsJson);
        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[하루 안심 지키미] 5분간 안부가 확인되지 않았습니다.",
          );
        }
      }
    }
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);

    Timer(const Duration(milliseconds: 400), () {
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
        title: const GradientText(
          "하루 안심 지키미",
          gradient: LinearGradient(colors: [Colors.orange, Colors.redAccent]),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFFCC80),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // 달력 섹션
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Text("4월", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) => Text(
                    ["월","화","수","목","금","토","일"][i],
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  )),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) => CircleAvatar(
                    radius: 14,
                    backgroundColor: (i == 4) ? Colors.orangeAccent : Colors.transparent,
                    child: Text(
                      "${20 + i}",
                      style: TextStyle(
                        color: (i == 4) ? Colors.white : Colors.black,
                        fontSize: 12,
                      ),
                    ),
                  )),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 12)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          // 입체 원형 버튼
          Center(
            child: GestureDetector(
              onTap: _onCheckIn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEFF0F3),
                  boxShadow: _isPressed 
                    ? [
                        BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4),
                        const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4),
                      ]
                    : [
                        BoxShadow(color: Colors.black.withOpacity(0.12), offset: const Offset(10, 10), blurRadius: 20),
                        const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                      ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Image.asset('assets/smile.png', width: 170, height: 170, fit: BoxFit.cover),
                    ),
                    Positioned(
                      bottom: 25,
                      child: Text(
                        "CLICK",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _isPressed ? Colors.orange : Colors.grey[400],
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          const Text("자동 문자 발송 작동 중", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
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
      if (contact != null) {
        setState(() {
          _contacts.add({
            'name': contact.displayName ?? "보호자",
            'number': contact.phones?.isNotEmpty == true ? contact.phones!.first.value ?? "" : ""
          });
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('contacts_list', json.encode(_contacts));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const GradientText(
          "보호자 및 권한 설정",
          gradient: LinearGradient(colors: [Colors.black87, Colors.blueGrey]),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFFCC80),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _contacts.length,
                itemBuilder: (context, i) => Card(
                  child: ListTile(
                    title: Text(_contacts[i]['name']!, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(_contacts[i]['number']!, style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20),
                      onPressed: () async {
                        setState(() => _contacts.removeAt(i));
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('contacts_list', json.encode(_contacts));
                      },
                    ),
                  ),
                ),
              ),
            ),
            ElevatedButton(onPressed: _addContact, child: const Text("보호자 추가", style: TextStyle(fontSize: 13))),
            const Divider(height: 40),
            const Text("수동 설정 가이드", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async => await [Permission.contacts, Permission.sms].request(),
                child: const Text("1. 권한 다시 승인", style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => openAppSettings(),
                child: const Text("2. 배터리 제한 해제", style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
