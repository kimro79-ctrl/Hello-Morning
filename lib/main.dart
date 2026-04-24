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
        scaffoldBackgroundColor: const Color(0xFFFDFCFB), // 아주 연한 베이지톤 배경
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}

// 그라데이션 텍스트 (타이틀용)
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
        selectedItemColor: const Color(0xFFFF8A65), // 파스텔 오렌지
        unselectedItemColor: const Color(0xFF90A4AE), // 차분한 그레이블루
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
  int _selectedMinutes = 5; 
  Timer? _timer;

  final List<Map<String, dynamic>> _options = [
    {'label': '5분', 'min': 5},
    {'label': '1시간', 'min': 60},
    {'label': '12시간', 'min': 720},
    {'label': '24시간', 'min': 1440},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(minutes: 1), (t) => _checkSafety());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedMinutes = p.getInt('selectedMinutes') ?? 5;
    });
  }

  Future<void> _checkSafety() async {
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheckIn');
    String? contacts = p.getString('contacts_list');
    if (last == null || contacts == null) return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    if (DateTime.now().difference(lastTime).inMinutes >= _selectedMinutes) {
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        String link = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
        List list = json.decode(contacts);
        for (var c in list) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심지키미] 미응답 감지!\n마지막 확인: $last\n위치확인: $link",
          );
        }
        _updateCheckInSilent();
      } catch (e) {
        // 위치 실패 시 문자만 발송
      }
    }
  }

  void _updateCheckInSilent() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    (await SharedPreferences.getInstance()).setString('lastCheckIn', now);
    if (mounted) setState(() { _lastCheckIn = now; });
  }

  void _onPressButton() async {
    setState(() => _isPressed = true);
    _updateCheckInSilent();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() { _isPressed = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const GradientText(
          "DAILY SAFETY",
          gradient: LinearGradient(colors: [Color(0xFFFF8A65), Color(0xFFE57373)]),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        backgroundColor: const Color(0xFFFFF3E0), // 파스텔 살구 탑
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _options.map((o) => ChoiceChip(
              label: Text(o['label'], style: TextStyle(color: _selectedMinutes == o['min'] ? Colors.white : const Color(0xFF546E7A))),
              selected: _selectedMinutes == o['min'],
              selectedColor: const Color(0xFFFFAB91),
              backgroundColor: Colors.white,
              onSelected: (val) async {
                setState(() => _selectedMinutes = o['min']);
                (await SharedPreferences.getInstance()).setInt('selectedMinutes', o['min']);
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 체크인 기록", style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14)),
          const SizedBox(height: 10),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF455A64))), // 딥네이비 컬러 텍스트
          const Spacer(),
          GestureDetector(
            onTap: _onPressButton,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,
                border: Border.all(color: _isPressed ? const Color(0xFFFFCCBC) : Colors.white, width: 12),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 25, spreadRadius: 5)],
              ),
              child: ClipOval(
                child: Image.asset('assets/smile.png', fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.favorite, size: 100, color: Color(0xFFFFAB91))),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(15)),
              child: Text(
                "${_selectedMinutes >= 60 ? _selectedMinutes ~/ 60 : _selectedMinutes}${_selectedMinutes >= 60 ? '시간' : '분'} 동안 무반응 시 보호자에게 비상 문자가 전송됩니다.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 50),
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

  // 요청하신 4가지 권한 로직 집중
  Future<void> _requestPermissions() async {
    // 1. 연락처 & 2. 문자 권한
    await [Permission.contacts, Permission.sms].request();
    // 3. 위치 권한 (앱 사용 중에만 허용)
    await Permission.location.request();
    // 4. 수동 백그라운드 (배터리 최적화 제외)
    await Permission.ignoreBatteryOptimizations.request();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("안심 설정을 위해 권한을 확인했습니다.")));
  }

  void _addContact() async {
    if (await Permission.contacts.isGranted) {
      final c = await ContactsService.openDeviceContactPicker();
      if (c != null) {
        setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
        (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
      }
    } else {
      await Permission.contacts.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 및 권한 설정", style: TextStyle(color: Color(0xFF455A64))), backgroundColor: const Color(0xFFFFF3E0), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFCCBC), child: Icon(Icons.person, color: Colors.white)),
              title: Text(_contacts[i]['name'] ?? "", style: const TextStyle(color: Color(0xFF455A64), fontWeight: FontWeight.bold)),
              subtitle: Text(_contacts[i]['number'] ?? "", style: const TextStyle(color: Color(0xFF78909C))),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE57373)), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(25.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _addContact,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE1F5FE), foregroundColor: const Color(0xFF0288D1), elevation: 0, minimumSize: const Size(double.infinity, 55)),
                  icon: const Icon(Icons.person_add_alt_1), label: const Text("보호자 연락처 추가"),
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8A65), foregroundColor: Colors.white, elevation: 2, minimumSize: const Size(double.infinity, 55)),
                  icon: const Icon(Icons.verified_user), label: const Text("필수 권한 및 백그라운드 설정"),
                ),
                const SizedBox(height: 15),
                const Text("위치 권한은 '앱 사용 중에만 허용'으로,\n배터리 최적화는 '제한 없음'으로 설정해 주세요.", 
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF90A4AE))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
