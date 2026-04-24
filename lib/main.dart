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
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFDFCFB), useMaterial3: true),
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
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _currentIndex, children: _screens),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: const Color(0xFFFF8A65),
      unselectedItemColor: const Color(0xFF90A4AE),
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 20), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 20), label: '설정'),
      ],
      selectedLabelStyle: const TextStyle(fontSize: 11),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  int _selectedHours = 1;
  Timer? _timer;
  bool _isPressed = false; // 터치 여부 확인용
  
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(minutes: 1), (t) => _checkAndSendSms());
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
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

  // 로직은 절대 건드리지 않았습니다.
  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null || last == "기록 없음") return;
    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    if (DateTime.now().difference(lastTime).inHours >= _selectedHours) {
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 10));
        String mapUrl = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
        List contacts = json.decode(contactsJson);
        for (var c in contacts) {
          await BackgroundSms.sendMessage(phoneNumber: c['number'], message: "[안심지키미] 응답 없음!\n마지막 확인: $last\n위치: $mapUrl");
        }
        _updateCheckIn();
      } catch (e) {
        List contacts = json.decode(contactsJson);
        for (var c in contacts) {
          await BackgroundSms.sendMessage(phoneNumber: c['number'], message: "[안심지키미] 응답 없음!\n마지막 확인: $last");
        }
        _updateCheckIn();
      }
    }
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    (await SharedPreferences.getInstance()).setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontSize: 15, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFF3E0).withOpacity(0.8),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // 1시간, 12시간, 24시간, 36시간 옵션 적용
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCCBC).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [1, 12, 24, 36].map((h) => ChoiceChip(
                label: Text("$h시간", style: const TextStyle(fontSize: 11)),
                selected: _selectedHours == h,
                selectedColor: const Color(0xFFFFAB91).withOpacity(0.8),
                backgroundColor: Colors.white.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (v) async {
                  setState(() => _selectedHours = h);
                  (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                },
              )).toList(),
            ),
          ),
          const Spacer(),
          const Text("마지막 확인 기록", style: TextStyle(color: Color(0xFF90A4AE), fontSize: 11)),
          const SizedBox(height: 5),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF546E7A))),
          const SizedBox(height: 40),
          
          // 누를 때만 컬러가 나오는 스위치 효과
          GestureDetector(
            onTapDown: (_) {
              _controller.forward();
              setState(() => _isPressed = true);
            },
            onTapUp: (_) {
              _controller.reverse();
              setState(() => _isPressed = false);
              _updateCheckIn();
            },
            onTapCancel: () {
              _controller.reverse();
              setState(() => _isPressed = false);
            },
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    if (_isPressed) // 누를 때만 레드핑크 은은하게 발생
                      BoxShadow(
                        color: const Color(0xFFFF80AB).withOpacity(0.4),
                        blurRadius: 35, spreadRadius: 12
                      )
                    else
                      const BoxShadow(color: Colors.black12, blurRadius: 10),
                  ],
                  border: Border.all(
                    color: _isPressed ? const Color(0xFFFF80AB).withOpacity(0.2) : Colors.transparent,
                    width: 6
                  ),
                ),
                child: ClipOval(
                  child: Image.asset('assets/smile.png', fit: BoxFit.contain, 
                    errorBuilder: (c,e,s) => const Icon(Icons.favorite, size: 80, color: Color(0xFFFF80AB))),
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE).withOpacity(0.6), borderRadius: BorderRadius.circular(15)),
              child: Text("$_selectedHours시간 미응답 시 보호자에게 위치 정보가 전송됩니다.",
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFE57373), fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 60),
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

  // 누락되었던 권한 설정 로직 추가
  Future<void> _requestPermissions() async {
    await [Permission.contacts, Permission.sms, Permission.location, Permission.ignoreBatteryOptimizations].request();
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("권한 설정을 완료했습니다.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 설정", style: TextStyle(fontSize: 14)), backgroundColor: const Color(0xFFFFF3E0), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE57373), size: 20), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
            child: Column(
              children: [
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE1F5FE), 
                    foregroundColor: const Color(0xFF0288D1),
                    elevation: 0, minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  child: const Text("연락처에서 추가", style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 12),
                // 빠져있던 권한 설정 버튼 복구
                ElevatedButton(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A65), 
                    foregroundColor: Colors.white,
                    elevation: 0, minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  child: const Text("모든 권한 허용하기", style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
