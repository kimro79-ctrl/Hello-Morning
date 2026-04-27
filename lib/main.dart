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
      scaffoldBackgroundColor: const Color(0xFFF5F5DC),
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
  // ✅ 수정: late를 사용하여 initState에서 화면 리스트 초기화 (에러 방지)
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [const HomeScreen(), const SettingScreen()];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNoticeDialog();
    });
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFFF8A65)),
            SizedBox(width: 10),
            Text("필수 기능 안내"),
          ],
        ),
        content: const Text("보호를 위해 위치(항상 허용)와 SMS 발송 권한이 필요합니다."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initPermissions();
            },
            child: const Text("확인 및 설정"),
          ),
        ],
      ),
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
  String _locationInfo = "위치 확인 중...";
  int _selectedHours = 1;
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
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  Future<void> _updateLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _locationInfo = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}");
    } catch (_) {
      if (mounted) setState(() => _locationInfo = "위치 확인 불가");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
              const SizedBox(height: 50),
              const Center(child: Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              Text(_locationInfo, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              const Spacer(),
              Text(_lastCheckIn, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 30),
              GestureDetector(
                onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
                onTapUp: (_) async {
                  setState(() => _isPressed = false); _controller.reverse();
                  String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                  final p = await SharedPreferences.getInstance();
                  await p.setString('lastCheckIn', now);
                  setState(() => _lastCheckIn = now);
                  _updateLocation();
                },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 200, height: 200,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, 
                      color: Colors.white, 
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/smile.png',
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Icon(Icons.face, size: 100, color: Colors.orange),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 2),
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
  void initState() { super.initState(); _loadData(); }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");
      _autoSmsEnabled = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 설정"), centerTitle: true),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("자동 문자 전송 활성화"),
            subtitle: const Text("응답이 없으면 보호자에게 위치를 보냅니다."),
            value: _autoSmsEnabled,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('auto_sms_enabled', v);
              setState(() => _autoSmsEnabled = v);
            },
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(_contacts[i]['name'] ?? '이름 없음'),
                subtitle: Text(_contacts[i]['number'] ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline), 
                  onPressed: () async {
                    setState(() => _contacts.removeAt(i));
                    (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                  }
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text("보호자 추가"),
                onPressed: () async {
                  if (await Permission.contacts.request().isGranted) {
                    final contact = await ContactsService.openDeviceContactPicker();
                    if (contact != null) {
                      setState(() => _contacts.add({
                        'name': contact.displayName, 
                        'number': contact.phones?.first.value ?? ''
                      }));
                      (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
