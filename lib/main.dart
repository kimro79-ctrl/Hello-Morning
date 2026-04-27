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
  
  // ✅ 핵심 수정 1: late를 사용하여 initState에서 화면을 정의해야 빌드 에러가 안 납니다.
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // ✅ 핵심 수정 2: 여기서 화면 리스트를 초기화합니다.
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
        title: const Text("필수 권한 안내"),
        content: const Text("위급 상황 시 보호자에게 위치를 알리기 위해 '항상 허용' 위치 권한과 SMS 권한이 필요합니다."),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _initPermissions(); }, child: const Text("확인"))
        ],
      ),
    );
  }

  Future<void> _initPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location].request();
    if (await Permission.location.isGranted) await Permission.locationAlways.request();
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
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(_controller);
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            Text("마지막 체크인: $_lastCheckIn"),
            const SizedBox(height: 30),
            GestureDetector(
              onTapDown: (_) => _controller.forward(),
              onTapUp: (_) async {
                _controller.reverse();
                String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                (await SharedPreferences.getInstance()).setString('lastCheckIn', now);
                setState(() => _lastCheckIn = now);
              },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 180, height: 180,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                  child: const Icon(Icons.favorite, size: 80, color: Color(0xFFFF8A65)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ 핵심 수정 3: 누락되기 쉬운 SettingScreen 클래스 전체 포함
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
      appBar: AppBar(title: const Text("설정"), centerTitle: true),
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
          Expanded(
            child: ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(_contacts[i]['name'] ?? '이름 없음'),
                subtitle: Text(_contacts[i]['number'] ?? ''),
                trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                  setState(() => _contacts.removeAt(i));
                  (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
                }),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("보호자 등록"),
              onPressed: () async {
                if (await Permission.contacts.request().isGranted) {
                  final contact = await ContactsService.openDeviceContactPicker();
                  if (contact != null) {
                    setState(() => _contacts.add({'name': contact.displayName, 'number': contact.phones?.first.value}));
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
