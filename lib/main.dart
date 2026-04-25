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
  String _currentLocationText = "위치 확인 중"; 
  int _selectedHours = 1; 
  bool _isLocating = false;
  bool _isPressed = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
    _loadData();
    _updateLocationDisplay();
  }

  void _showResultDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인"))],
      ),
    );
  }

  Future<void> _updateLocationDisplay() async {
    if (!mounted) return;
    setState(() { _isLocating = true; _currentLocationText = "위치 수신 중"; });
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted) {
        setState(() {
          _isLocating = false;
          _currentLocationText = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLocating = false; _currentLocationText = "위치 확인 불가"; });
    }
  }

  // ✅ 제안하신 문자 문구 적용 (링크 제외)
  Future<void> _testSmsSend() async {
    final p = await SharedPreferences.getInstance();
    String? contactsJson = p.getString('contacts_list');
    
    if (contactsJson == null || contactsJson == "[]") {
      _showResultDialog("알림", "등록된 보호자 연락처가 없습니다.");
      return;
    }

    List contacts = json.decode(contactsJson);
    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
    
    // 좌표 형식 가공 (예: 37.123456, 127.123456)
    String coords = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";

    for (var c in contacts) {
      String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
      
      // 사용자님이 요청하신 문구 구성
      String messageBody = "안녕하세요, '안심 지키미'입니다. ${c['name']}님께 등록된 사용자의 안부 확인이 지연되고 있습니다. 확인 부탁드립니다.\n\n좌표: $coords\n위 좌표를 구글맵에서 검색하세요.";

      try {
        SmsStatus result = await BackgroundSms.sendMessage(
          phoneNumber: cleanNumber, 
          message: messageBody,
        );

        if (result == SmsStatus.success) {
          _showResultDialog("전송 성공", "${c['name']}님께 문자를 보냈습니다.");
        } else {
          _showResultDialog("전송 실패", "상태: $result\n권한 및 보안 설정을 확인하세요.");
        }
      } catch (e) {
        _showResultDialog("오류", "에러 발생: $e");
      }
    }
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
    _updateLocationDisplay();
    _testSmsSend();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 15),
          const Text("중앙 버튼을 누르면 보호자에게 안부 문자가 발송됩니다.", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const Spacer(),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          GestureDetector(
            onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
            onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 200, height: 200,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.favorite, size: 80, color: Colors.orange))),
              ),
            ),
          ),
          const Spacer(),
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
  List _contacts = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _contacts = json.decode(p.getString('contacts_list') ?? "[]"));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정")),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          ElevatedButton(
            onPressed: () async {
              if (await Permission.contacts.request().isGranted) {
                final c = await ContactsService.openDeviceContactPicker();
                if (c != null && c.phones!.isNotEmpty) {
                  setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
                  (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                }
              }
            },
            child: const Text("보호자 추가"),
          ),
          ElevatedButton(onPressed: () => openAppSettings(), child: const Text("권한 설정 이동")),
        ],
      ),
    );
  }
}
