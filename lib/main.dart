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
      title: '하루 한번 안심지킴이',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFDFCFB),
        useMaterial3: true,
      ),
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
        selectedItemColor: const Color(0xFFFF8A65),
        unselectedItemColor: const Color(0xFF90A4AE),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          // 사람 둘이 손잡은 느낌의 아이콘으로 변경
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: '설정'),
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
            message: "[하루 한번 안부 지킴이] 미응답 감지!\n마지막 확인: $last\n위치: $link",
          );
        }
        _updateCheckInSilent();
      } catch (e) { }
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
          "하루 한번 안심지킴이",
          gradient: LinearGradient(colors: [Color(0xFFFF8A65), Color(0xFFE57373)]),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        backgroundColor: const Color(0xFFFFF3E0),
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
          Text(_lastCheckIn, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF455A64))),
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
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.face_retouching_natural, size: 100, color: Color(0xFFFFAB91))),
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
                "${_selectedMinutes >= 60 ? _selectedMinutes ~/ 60 : _selectedMinutes}${_selectedMinutes >= 60 ? '시간' : '분'} 미응답 시 비상 문자가 전송됩니다.",
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

  // 권한 요청 시 팝업이 확실히 뜨도록 개별 확인 및 요청
  Future<void> _requestPermissions() async {
    // 1. 연락처 권한 (이게 수락되어야 주소록 창이 뜸)
    var contactStatus = await Permission.contacts.status;
    if (!contactStatus.isGranted) {
      await Permission.contacts.request();
    }

    // 2. 문자 권한
    var smsStatus = await Permission.sms.status;
    if (!smsStatus.isGranted) {
      await Permission.sms.request();
    }

    // 3. 위치 권한
    var locStatus = await Permission.location.status;
    if (!locStatus.isGranted) {
      await Permission.location.request();
    }

    // 4. 배터리 최적화 제외 (백그라운드 유지)
    await Permission.ignoreBatteryOptimizations.request();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("권한 설정을 확인했습니다.")));
  }

  void _addContact() async {
    // 주소록을 열기 전에 권한을 다시 한 번 명시적으로 확인
    PermissionStatus status = await Permission.contacts.request();
    
    if (status.isGranted) {
      try {
        final Contact? c = await ContactsService.openDeviceContactPicker();
        if (c != null && c.phones!.isNotEmpty) {
          setState(() => _contacts.add({
            'name': c.displayName ?? "이름없음", 
            'number': c.phones?.first.value ?? ""
          }));
          final p = await SharedPreferences.getInstance();
          await p.setString('contacts_list', json.encode(_contacts));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("주소록을 불러오는 중 오류가 발생했습니다.")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("연락처 권한을 허용해야 추가가 가능합니다.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 등록", style: TextStyle(color: Color(0xFF455A64))), backgroundColor: const Color(0xFFFFF3E0), centerTitle: true),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE1F5FE), foregroundColor: const Color(0xFF0288D1), minimumSize: const Size(double.infinity, 55)),
                  icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text("보호자 연락처 추가"),
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8A65), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
                  icon: const Icon(Icons.lock_open_rounded), label: const Text("모든 권한 허용하기"),
                ),
                const SizedBox(height: 10),
                const Text("연락처 팝업이 안 뜨면 '모든 권한 허용하기'를 먼저 누르세요.", 
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF90A4AE))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
