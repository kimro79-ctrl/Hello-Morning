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
  // ✅ SettingScreen 클래스가 하단에 정의되어 있어야 에러가 나지 않습니다.
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
  String _currentLocationText = "위치 확인 중..."; 
  int _selectedHours = 1; 
  Timer? _timer;
  bool _isPressed = false; // 연핑크 테두리 상태

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
        String message = "[안부 지킴이] 응답 지연!\n좌표: ${pos.latitude},${pos.longitude}";
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
      appBar: AppBar(title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_currentLocationText, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF8A65))),
            const SizedBox(height: 20),
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
            Text(_lastCheckIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            GestureDetector(
              onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
              onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
              onTapCancel: () { setState(() => _isPressed = false); _controller.reverse(); },
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: _isPressed ? const Color(0xFFFFC1CC) : Colors.black12, 
                        blurRadius: _isPressed ? 25 : 10,
                        spreadRadius: _isPressed ? 8 : 2,
                      )
                    ],
                    border: Border.all(color: _isPressed ? const Color(0xFFFFC1CC) : Colors.transparent, width: 4),
                  ),
                  child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.favorite, size: 80, color: Colors.orange))),
                ),
              ),
            ),
            const Spacer(),
            const Text("미응답 시 보호자에게 위치가 전송됩니다.", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ✅ 오류의 원인이었던 SettingScreen 클래스를 추가했습니다.
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
      appBar: AppBar(title: const Text("설정")),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("자동 문자 전송"),
            value: _autoSmsEnabled,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('auto_sms_enabled', v);
              setState(() => _autoSmsEnabled = v);
            },
          ),
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                setState(() => _contacts.removeAt(i));
                (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
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
        ],
      ),
    );
  }
}
