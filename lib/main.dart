import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart'; // 위치 패키지 추가
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

// 그라데이션 텍스트 위젯 (타이틀용)
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
  int _selectedMinutes = 1440; // 기본 24시간
  Timer? _autoCheckTimer;

  final List<Map<String, dynamic>> _options = [
    {'label': '5분', 'min': 5},
    {'label': '12시간', 'min': 720},
    {'label': '24시간', 'min': 1440},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
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
      _selectedMinutes = prefs.getInt('selectedMinutes') ?? 1440;
    });
  }

  // 위치 정보 가져오기 및 문자 발송 핵심 로직
  Future<void> _checkAutoSms() async {
    final prefs = await SharedPreferences.getInstance();
    String? last = prefs.getString('lastCheckIn');
    String? contacts = prefs.getString('contacts_list');
    
    if (last == null || contacts == null) return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int diff = DateTime.now().difference(lastTime).inMinutes;

    if (diff >= _selectedMinutes) {
      try {
        // 1. 위치 권한 확인 및 현재 위치 획득
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
        );
        String mapLink = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
        
        // 2. 보호자 리스트 불러오기
        List list = json.decode(contacts);
        for (var c in list) {
          // 3. 문자 발송
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[하루안심] ${_selectedMinutes >= 60 ? _selectedMinutes ~/ 60 : _selectedMinutes}${_selectedMinutes >= 60 ? '시간' : '분'} 미응답 발생.\n마지막 확인: $last\n위치: $mapLink",
          );
        }
        // 발송 후 자동 갱신 (테스트 중복 방지)
        _updateCheckIn();
      } catch (e) {
        // 위치 획득 실패 시에도 긴급 문자는 발송
        List list = json.decode(contacts);
        for (var c in list) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[하루안심] 미응답 발생. 위치 확인 불가.\n마지막 확인: $last",
          );
        }
      }
    }
  }

  void _updateCheckIn() async {
    setState(() => _isPressed = true);
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastCheckIn', now);
    
    Future.delayed(const Duration(milliseconds: 500), () {
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
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // 시간 선택 칩 (5분 테스트 포함)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _options.map((opt) => ChoiceChip(
              label: Text(opt['label']),
              selected: _selectedMinutes == opt['min'],
              onSelected: (val) async {
                setState(() => _selectedMinutes = opt['min']);
                (await SharedPreferences.getInstance()).setInt('selectedMinutes', opt['min']);
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 안부 확인", style: TextStyle(color: Colors.grey)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          // 메인 이미지 버튼 (사용자님의 smile.png 사용)
          GestureDetector(
            onTap: _updateCheckIn,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: _isPressed ? Colors.orangeAccent : Colors.white, width: 10),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/smile.png', // 등록하신 이미지 경로
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.face, size: 100, color: Colors.orangeAccent),
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              "${_selectedMinutes >= 60 ? _selectedMinutes ~/ 60 : _selectedMinutes}${_selectedMinutes >= 60 ? '시간' : '분'} 동안 미응답 시 보호자에게 위치가 발송됩니다.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// 설정 화면 (보호자 연락처 등록 및 권한 요청)
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
      setState(() => _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i))));
    }
  }

  void _addContact() async {
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null) {
        String name = contact.displayName ?? "보호자";
        String number = contact.phones?.isNotEmpty == true ? contact.phones!.first.value ?? "" : "";
        setState(() => _contacts.add({'name': name, 'number': number}));
        (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 등록"), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, i) => ListTile(
                leading: const Icon(Icons.person, color: Colors.orangeAccent),
                title: Text(_contacts[i]['name']!),
                subtitle: Text(_contacts[i]['number']!),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () async {
                    setState(() => _contacts.removeAt(i));
                    (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                  },
                ),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _addContact,
            icon: const Icon(Icons.add),
            label: const Text("연락처 추가"),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () async => await [Permission.sms, Permission.location, Permission.locationAlways].request(),
            child: const Text("모든 권한 허용하기"),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
