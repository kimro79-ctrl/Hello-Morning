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
      scaffoldBackgroundColor: const Color(0xFFF5F5DC), // 진한 아이보리 유지
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNoticeDialog();
    });
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.security, color: Color(0xFFFF8A65)),
              SizedBox(width: 10),
              Text("필수 기능 안내", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("안녕하세요. '1인가구 안심 지키미'입니다.\n", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("사용자의 안전을 위해 아래 두 가지 권한이 반드시 필요합니다.", style: TextStyle(fontSize: 13, color: Colors.black87)),
              SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("1. ", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
                  Expanded(child: Text("백그라운드 위치 (항상 허용)\n위급 상황 발생 시 정확한 위치 파악을 위해 필요합니다.", style: TextStyle(fontSize: 12))),
                ],
              ),
              SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("2. ", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
                  Expanded(child: Text("SMS 발송\n설정된 시간 동안 응답이 없으면 보호자에게 문자를 전송합니다.", style: TextStyle(fontSize: 12))),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _initPermissions();
              },
              child: const Text("확인 및 권한 설정", style: TextStyle(color: Color(0xFF5C6BC0), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location].request();
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
      unselectedFontSize: 11,
      selectedFontSize: 11,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 20), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 20), label: '설정'),
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
  String _locationInfo = "위치 확인 중..."; 
  int _selectedHours = 1; 
  Timer? _timer;
  bool _isPressed = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(_controller);
    _loadData();
    _updateLocation();
    // ✅ 3분 주기 자동 체크 로직 유지
    _timer = Timer.periodic(const Duration(minutes: 3), (t) => _checkAndSendSms());
  }

  Future<void> _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _locationInfo = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}");
    } catch (e) {
      if (mounted) setState(() => _locationInfo = "위치 확인 불가");
    }
  }

  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null || contactsJson == "[]") return;
    
    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int limitMin = _selectedHours == 0 ? 5 : _selectedHours * 60;
    
    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      List contacts = json.decode(contactsJson);
      for (var c in contacts) {
        await BackgroundSms.sendMessage(
          phoneNumber: c['number'], 
          message: "[1인가구 안심 지키미] 응답 지연 발생!\n좌표: ${pos.latitude},${pos.longitude}"
        );
      }
      _updateCheckIn();
    }
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
    _updateLocation();
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFE3F2FD), Color(0xFFF5F5DC)],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Center(
                child: Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5C6BC0))),
              ),
              const SizedBox(height: 8),
              Text(_locationInfo, style: const TextStyle(color: Color(0xFF5C6BC0), fontSize: 12, fontWeight: FontWeight.w400)),
              const SizedBox(height: 25),
              Wrap(
                spacing: 6,
                children: [0, 1, 12, 24].map((h) => ChoiceChip(
                  label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 11)),
                  selected: _selectedHours == h,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (v) async {
                    setState(() => _selectedHours = h);
                    (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                  },
                )).toList(),
              ),
              const Spacer(flex: 2),
              Text(_lastCheckIn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              const SizedBox(height: 30),
              GestureDetector(
                onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
                onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
                onTapCancel: () { setState(() => _isPressed = false); _controller.reverse(); },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white, 
                      border: Border.all(color: Colors.black.withOpacity(0.05), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: _isPressed ? const Color(0xFFFFC1CC).withOpacity(0.6) : Colors.black.withOpacity(0.03), 
                          blurRadius: _isPressed ? 25 : 15, spreadRadius: _isPressed ? 8 : 1,
                        )
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/smile.png', // ✅ 중앙 버튼은 smile.png 유지
                        fit: BoxFit.cover,
                        errorBuilder: (c,e,s) => const Icon(Icons.face, size: 100, color: Colors.orange)
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
              const Text("미응답 시 보호자에게 위치가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: 40),
            ],
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
      appBar: AppBar(
        title: const Text("설정", style: TextStyle(fontSize: 16)), 
        backgroundColor: Colors.transparent, 
        centerTitle: true,
        elevation: 0
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE0B2).withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.security, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("권한 설정 확인", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const Text("위치 권한을 '항상 허용'으로 설정해야 보호가 가능합니다.", style: TextStyle(fontSize: 11, color: Colors.black87)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => openAppSettings(),
                        child: const Text("설정 바로가기 >", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("자동 문자 전송 활성화", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Transform.scale(
                  scale: 0.9,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _autoSmsEnabled ? const Color(0xFFFF8A65).withOpacity(0.5) : Colors.black12,
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Switch(
                      value: _autoSmsEnabled,
                      activeColor: Colors.white,
                      activeTrackColor: const Color(0xFFFF7043),
                      inactiveThumbColor: Colors.grey[600],
                      inactiveTrackColor: Colors.grey[300],
                      onChanged: (v) async {
                        final p = await SharedPreferences.getInstance();
                        await p.setBool('auto_sms_enabled', v);
                        setState(() => _autoSmsEnabled = v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 30),
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              dense: true,
              leading: const CircleAvatar(radius: 14, backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.person, size: 16, color: Colors.blue)),
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 13)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text("보호자 추가", style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
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
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
