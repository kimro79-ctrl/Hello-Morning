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
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFEFF0F3), useMaterial3: true),
      home: const MainNavigation(),
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
  String? _lastSentKey;
  int _selectedThresholdHour = 24;
  final List<int> _thresholdOptions = [1, 12, 24, 36];

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
      _selectedThresholdHour = prefs.getInt('thresholdHour') ?? 24;
    });
  }

  Future<String> _getLocationLink() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      return "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
    } catch (e) {
      return "(위치 확인 불가)";
    }
  }

  Future<void> _checkAutoSms() async {
    final prefs = await SharedPreferences.getInstance();
    String? lastTimeStr = prefs.getString('lastCheckIn');
    String? contactsJson = prefs.getString('contacts_list');
    if (lastTimeStr != null && contactsJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      if (DateTime.now().difference(lastTime).inHours >= _selectedThresholdHour) {
        String key = DateFormat('yyyyMMddHHmm').format(DateTime.now());
        if (_lastSentKey != key && await Permission.sms.isGranted) {
          String mapLink = await _getLocationLink();
          List<dynamic> contacts = json.decode(contactsJson);
          for (var c in contacts) {
            await BackgroundSms.sendMessage(
              phoneNumber: c['number'],
              message: "[하루안부] ${_selectedThresholdHour}시간 미응답.\n마지막 확인: $lastTimeStr\n위치: $mapLink",
            );
          }
          _lastSentKey = key;
        }
      }
    }
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    _lastSentKey = null;
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = now; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("하루 안심 지키미", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFFFCC80), centerTitle: true),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _thresholdOptions.map((h) => ActionChip(
              label: Text("${h}h"),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('thresholdHour', h);
                setState(() => _selectedThresholdHour = h);
              },
              backgroundColor: _selectedThresholdHour == h ? Colors.orangeAccent : Colors.white,
            )).toList(),
          ),
          const Spacer(),
          Text("마지막 확인: $_lastCheckIn", style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => _onCheckIn(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: const Color(0xFFEFF0F3),
                border: Border.all(color: _isPressed ? const Color(0xFFFFD1DC) : Colors.white, width: _isPressed ? 10 : 2),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(5, 5))],
              ),
              child: const Center(child: Icon(Icons.face, size: 100, color: Colors.orangeAccent)),
            ),
          ),
          const Spacer(),
          Text("$_selectedThresholdHour시간 미응답 시 보호자에게 위치 문자가 발송됩니다", style: TextStyle(color: Colors.grey[500], fontSize: 11)),
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
    if (data != null) setState(() => _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i))));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정")),
      body: Column(
        children: [
          Expanded(child: ListView.builder(itemCount: _contacts.length, itemBuilder: (context, i) => ListTile(title: Text(_contacts[i]['name']!), subtitle: Text(_contacts[i]['number']!)))),
          ElevatedButton(onPressed: () async => await [Permission.sms, Permission.location].request(), child: const Text("권한 허용하기")),
        ],
      ),
    );
  }
}
