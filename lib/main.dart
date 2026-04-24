import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
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

// 상단 앱바 타이틀용 그라데이션 텍스트
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
  String? _lastSentKey; // 중복 발송 방지
  
  // 타이머 옵션 및 선택된 시간
  int _selectedThresholdHour = 24;
  final List<int> _thresholdOptions = [1, 12, 24, 36];

  @override
  void initState() {
    super.initState();
    _loadData();
    // 1분마다 상태를 체크합니다.
    _autoCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) => _checkAutoSms());
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  // 저장된 데이터 불러오기
  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해 주세요";
      _selectedThresholdHour = prefs.getInt('thresholdHour') ?? 24;
    });
  }

  // 발송 주기 변경 및 저장
  Future<void> _updateThreshold(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('thresholdHour', hour);
    setState(() => _selectedThresholdHour = hour);
  }

  // 미응답 시 위치 정보 링크 생성 (구글 지도)
  Future<String> _getLocationLink() async {
    try {
      // 위치 서비스 활성화 여부 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return "(위치 서비스가 꺼져 있음)";

      // 위치 권한 확인
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return "(위치 권한 거부됨)";
      }

      // 현재 좌표 가져오기
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      return "https://www.google.com/maps?q=${position.latitude},${position.longitude}";
    } catch (e) {
      return "(위치 확인 실패)";
    }
  }

  // 자동 문자 발송 로직
  Future<void> _checkAutoSms() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastTimeStr = prefs.getString('lastCheckIn');
    String? contactsJson = prefs.getString('contacts_list');
    
    if (lastTimeStr != null && contactsJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      DateTime now = DateTime.now();
      
      // 설정된 시간이 지났는지 확인
      if (now.difference(lastTime).inHours >= _selectedThresholdHour) {
        String currentMinuteKey = DateFormat('yyyyMMddHHmm').format(now);
        // 이미 해당 분에 보낸 적이 없다면 실행
        if (_lastSentKey != currentMinuteKey) {
          if (await Permission.sms.isGranted) {
            String mapLink = await _getLocationLink(); // 발송 시점에만 위치 조회
            List<dynamic> contacts = json.decode(contactsJson);
            for (var c in contacts) {
              await BackgroundSms.sendMessage(
                phoneNumber: c['number'],
                message: "[하루안부] ${_selectedThresholdHour}시간 동안 확인이 없습니다.\n마지막 확인: $lastTimeStr\n위치: $mapLink\n보호자의 확인이 필요합니다.",
              );
            }
            _lastSentKey = currentMinuteKey;
          }
        }
      }
    }
  }

  // 안부 확인(Click) 버튼 동작
  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    _lastSentKey = null; // 체크인 시 발송 기록 초기화

    // 버튼 터치 효과를 위한 지연
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
          // 타이머 선택 섹션
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _thresholdOptions.map((hour) {
                bool isSelected = _selectedThresholdHour == hour;
                return GestureDetector(
                  onTap: () => _updateThreshold(hour),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orangeAccent : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
                    ),
                    child: Text(
                      "${hour}시간",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.orangeAccent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 12)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          
          // 메인 버튼 (연핑크 터치 효과 적용)
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
                  // 터치 시 연핑크 테두리
                  border: Border.all(
                    color: _isPressed ? const Color(0xFFFFD1DC) : Colors.white,
                    width: _isPressed ? 10 : 2,
                  ),
                  boxShadow: _isPressed 
                    ? [BoxShadow(color: const Color(0xFFFFD1DC).withOpacity(0.8), blurRadius: 25, spreadRadius: 5)]
                    : [
                        BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(10, 10), blurRadius: 20),
                        const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                      ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Image.asset('assets/smile.png', width: 170, height: 170, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.face, size: 100, color: Colors.orangeAccent)),
                    ),
                    Positioned(
                      bottom: 25,
                      child: Text(
                        "CLICK",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _isPressed ? const Color(0xFFFFB6C1) : Colors.grey[400],
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
          // 하단 안내 문구 (연한 회색 톤)
          Text(
            "$_selectedThresholdHour시간 동안 확인이 없으면 보호자에게 문자가 발송됩니다",
            style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500),
          ),
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
    if (data != null) {
      setState(() => _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i))));
    }
  }

  void _addContact() async {
    if (_contacts.length >= 5) return;
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null) {
        String name = contact.displayName ?? "보호자";
        String number = contact.phones?.isNotEmpty == true ? contact.phones!.first.value ?? "" : "";
        setState(() => _contacts.add({'name': name, 'number': number}));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('contacts_list', json.encode(_contacts));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFFFCC80)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _contacts.length,
                itemBuilder: (context, i) => Card(
                  child: ListTile(
                    title: Text(_contacts[i]['name']!),
                    subtitle: Text(_contacts[i]['number']!),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
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
            ElevatedButton(onPressed: _addContact, child: const Text("보호자 추가")),
            const Divider(height: 40),
            // 권한 통합 관리 섹션
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () async => await [Permission.sms, Permission.location].request(), child: const Text("SMS 및 위치 권한 확인"))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => openAppSettings(), child: const Text("시스템 설정 (배터리 최적화 해제)"))),
          ],
        ),
      ),
    );
  }
}
