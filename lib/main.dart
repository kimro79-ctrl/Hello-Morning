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
      scaffoldBackgroundColor: const Color(0xFFFFFDF9), // 기본 배경 아이보리
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
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.contacts,
      Permission.location,
    ].request();

    if (statuses[Permission.location]!.isGranted) {
      if (!(await Permission.locationAlways.isGranted)) {
        await Permission.locationAlways.request();
      }
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
    _timer = Timer.periodic(const Duration(minutes: 5), (t) => _checkAndSendSms());
  }

  Future<void> _updateLocationDisplay() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) {
        setState(() => _currentLocationText = "좌표: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}");
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
      List contacts = json.decode(contactsJson);
      for (var c in contacts) {
        String message = "[안부 지킴이] 사용자 응답 지연!\n좌표: ${pos.latitude},${pos.longitude}";
        await BackgroundSms.sendMessage(phoneNumber: c['number'], message: message);
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

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  @override
  void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // ✅ 파스텔 블루(상단)에서 연한 아이보리(중앙)로 이어지는 그라데이션
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F2FD), // 상단: 파스텔 블루 (Light Blue 50)
              Color(0xFFFFFDF9), // 중앙/하단: 부드러운 아이보리 (Ivory)
            ],
            stops: [0.0, 0.5], // 50% 지점까지 자연스럽게 섞임
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              children: [
                const SizedBox(height: 50),
                const Text(
                  "안심 지키미",
                  style: TextStyle(
                    fontSize: 28, 
                    fontWeight: FontWeight.bold, 
                    color: Color(0xFF5C6BC0) // 블루 배경에 어울리는 차분한 남색 계열 텍스트
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6), 
                    borderRadius: BorderRadius.circular(20)
                  ),
                  child: Text(
                    _currentLocationText, 
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))
                  ),
                ),
                const SizedBox(height: 30),
                Wrap(
                  spacing: 8,
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
                Text(
                  _lastCheckIn, 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)
                ),
                const SizedBox(height: 40),
                // ✅ 스마일 버튼 + 연핑크 글로우 유지
                GestureDetector(
                  onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
                  onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
                  onTapCancel: () { setState(() => _isPressed = false); _controller.reverse(); },
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 220, height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: _isPressed ? const Color(0xFFFFC1CC).withOpacity(0.8) : Colors.black.withOpacity(0.04), 
                            blurRadius: _isPressed ? 30 : 15,
                            spreadRadius: _isPressed ? 10 : 2,
                          )
                        ],
                        border: Border.all(
                          color: _isPressed ? const Color(0xFFFFC1CC) : Colors.transparent, 
                          width: 5
                        ),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/smile.png', 
                          width: 160, 
                          errorBuilder: (c,e,s) => const Icon(Icons.face, size: 100, color: Colors.orange)
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  "미응답 시 보호자에게 위치가 전송됩니다.", 
                  style: TextStyle(color: Colors.grey, fontSize: 13)
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
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
  bool _autoSmsEnabled = false;

  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");
      _autoSmsEnabled = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정"), backgroundColor: const Color(0xFFE3F2FD)),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("자동 문자 전송 활성화"),
            value: _autoSmsEnabled,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('auto_sms_enabled', v);
              setState(() => _autoSmsEnabled = v);
            },
          ),
          const Divider(),
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text("보호자 추가"),
              onPressed: () async {
                if (await Permission.contacts.request().isGranted) {
                  final c = await ContactsService.openDeviceContactPicker();
                  if (c != null) {
                    setState(() => _contacts.add({'name': c.displayName, 'number': c.phones?.first.value}));
                    (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
