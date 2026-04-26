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
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: const Color(0xFFFDFCFB),
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
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
  }

  Future<void> _requestAllPermissions() async {
    // SMS, 위치, 연락처 권한 요청
    await [Permission.sms, Permission.location, Permission.contacts].request();
    // 백그라운드 위치 권한은 별도 요청
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _currentIndex, children: _screens),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: const Color(0xFFFF8A65),
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
      ],
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  String _currentLocationText = "위치 확인 중..."; 
  int _selectedHours = 1; 
  Timer? _timer;
  bool _isPressed = false; // ✅ 연핑크 테두리 효과용 상태값

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // ✅ 누르는 애니메이션 속도 조절
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
    _loadData();
    _updateLocationDisplay();
    _timer = Timer.periodic(const Duration(minutes: 5), (t) => _checkAndSendSms());
  }

  Future<void> _updateLocationDisplay() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) {
        setState(() {
          _currentLocationText = "좌표: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _currentLocationText = "위치 확인 불가");
    }
  }

  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null || contactsJson == "[]") return;
    
    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int targetMin = _selectedHours == 0 ? 5 : _selectedHours * 60;
    
    if (DateTime.now().difference(lastTime).inMinutes >= targetMin) {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      String coords = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
      List contacts = json.decode(contactsJson);
      
      for (var c in contacts) {
        String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
        String messageBody = "['안부 지킴이'] 사용자 안부 확인 지연.\n좌표: $coords\n구글맵에서 검색하세요.";
        await BackgroundSms.sendMessage(phoneNumber: cleanNumber, message: messageBody);
      }
      _updateCheckIn();
    }
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
    _updateLocationDisplay();
  }

  @override
  void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(_currentLocationText, style: const TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 10,
              children: [0, 1, 12, 24].map((h) => ChoiceChip(
                label: Text(h == 0 ? "5분" : "$h시간"),
                selected: _selectedHours == h,
                onSelected: (v) async {
                  setState(() => _selectedHours = h);
                  (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                },
              )).toList(),
            ),
            const Spacer(),
            Text("마지막 확인: $_lastCheckIn", style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            
            // ✅ 사용자님의 이미지 + 애니메이션 + 연핑크 테두리 효과
            GestureDetector(
              onTapDown: (_) {
                setState(() => _isPressed = true); // 테두리 켜기
                _controller.forward();
              },
              onTapUp: (_) {
                setState(() => _isPressed = false); // 테두리 끄기
                _controller.reverse();
                _updateCheckIn();
              },
              onTapCancel: () {
                setState(() => _isPressed = false);
                _controller.reverse();
              },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: Colors.white, 
                    // ✅ 누를 때 연핑크색(Color(0xFFFFC1CC)) 번짐 효과
                    boxShadow: [
                      BoxShadow(
                        color: _isPressed ? const Color(0xFFFFC1CC).withOpacity(0.6) : Colors.black.withOpacity(0.05), 
                        blurRadius: _isPressed ? 30 : 15, 
                        spreadRadius: _isPressed ? 10 : 2
                      )
                    ],
                    // ✅ 테두리 연핑크색 적용
                    border: Border.all(
                      color: _isPressed ? const Color(0xFFFFC1CC) : Colors.transparent, 
                      width: 4
                    ),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/smile.png', // ✅ 사용자님의 에셋 적용
                      width: 160, 
                      errorBuilder: (c, e, s) => const Icon(Icons.face, size: 100, color: Colors.orange)
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            const Text("미응답 시 보호자에게 위치가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// (이후 SettingScreen 코드는 이전과 동일하므로 생략하거나 기존 코드를 유지하시면 됩니다.)
