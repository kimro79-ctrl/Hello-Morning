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
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFEFF0F3), useMaterial3: true),
      home: const MainNavigation(),
    );
  }
}

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
  String? _lastSentTime; // 마지막으로 문자를 보낸 '분'을 저장해 중복 방지

  @override
  void initState() {
    super.initState();
    _loadData();
    // 30초마다 더 촘촘하게 체크 (타이밍 놓침 방지)
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) => _checkAutoSms());
  }

  @override
  void dispose() { _autoCheckTimer?.cancel(); super.dispose(); }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해 주세요");
  }

  // 핵심: 문자 발송 로직 강화
  Future<void> _checkAutoSms() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastTimeStr = prefs.getString('lastCheckIn');
    String? contactsJson = prefs.getString('contacts_list');
    
    if (lastTimeStr != null && contactsJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      DateTime now = DateTime.now();
      int difference = now.difference(lastTime).inMinutes;

      // 5분 이상 지났고, 현재 '분'에 문자를 보낸 적이 없을 때만 실행
      String currentMinute = DateFormat('yyyyMMddHHmm').format(now);
      if (difference >= 5 && _lastSentTime != currentMinute) {
        if (await Permission.sms.isGranted) {
          List<dynamic> contacts = json.decode(contactsJson);
          for (var c in contacts) {
            await BackgroundSms.sendMessage(
              phoneNumber: c['number'],
              message: "[하루 안심 지키미] 5분간 안부가 확인되지 않았습니다. 현재시간: ${DateFormat('HH:mm').format(now)}",
            );
          }
          _lastSentTime = currentMinute; // 발송 기록 업데이트
          debugPrint("자동 문자 발송 완료: $currentMinute");
        }
      }
    }
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    _lastSentTime = null; // 체크인 시 발송 기록 초기화 (다시 5분 카운트)

    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = now; });
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
        backgroundColor: const Color(0xFFFFCC80), centerTitle: true, elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 12)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          
          // --- 연핑크 터치 효과 버튼 ---
          Center(
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => _onCheckIn(),
              onTapCancel: () => setState(() => _isPressed = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEFF0F3),
                  border: Border.all(
                    color: _isPressed ? const Color(0xFFFFD1DC) : Colors.white,
                    width: _isPressed ? 8 : 2,
                  ),
                  boxShadow: _isPressed 
                    ? [BoxShadow(color: const Color(0xFFFFD1DC).withOpacity(0.6), blurRadius: 20, spreadRadius: 5)]
                    : [
                        BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(10, 10), blurRadius: 20),
                        const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                      ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(child: Image.asset('assets/smile.png', width: 170, height: 170, fit: BoxFit.cover)),
                    Positioned(
                      bottom: 25,
                      child: Text("CLICK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _isPressed ? const Color(0xFFFFB6C1) : Colors.grey[400], letterSpacing: 2.0)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          const Text("5분 미응답 시 자동 문자 발송", style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
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
  void initState() { super.initState(); _loadContacts(); }
  void _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('contacts_list');
    if (data != null) setState(() => _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i))));
  }
  void _addContact() async {
    if (_contacts.length >= 5) return;
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null) {
        setState(() => _contacts.add({'name': contact.displayName ?? "보호자", 'number': contact.phones?.first.value ?? ""}));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('contacts_list', json.encode(_contacts));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("설정", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFCC80),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(child: ListView.builder(itemCount: _contacts.length, itemBuilder: (context, i) => Card(child: ListTile(title: Text(_contacts[i]['name']!), subtitle: Text(_contacts[i]['number']!), trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () async {
              setState(() => _contacts.removeAt(i));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('contacts_list', json.encode(_contacts));
            }))))),
            ElevatedButton(onPressed: _addContact, child: const Text("보호자 추가")),
            const Divider(height: 40),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () async => await [Permission.sms].request(), child: const Text("SMS 권한 확인"))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => openAppSettings(), child: const Text("배터리 최적화 해제 (필수)"))),
          ],
        ),
      ),
    );
  }
}
