import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
      selectedFontSize: 12, // 텍스트 크기 상향
      unselectedFontSize: 11,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 22), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 22), label: '설정'),
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
  String _currentW3W = "위치 확인 중";
  int _selectedHours = 1; 
  Timer? _timer;
  Timer? _dotTimer;
  int _dotCount = 0;
  bool _isLocating = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  final String w3wApiKey = "WTE21N79"; 

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
    _loadData();
    _updateW3WDisplay();
    _timer = Timer.periodic(const Duration(minutes: 1), (t) => _checkAndSendSms());
    
    // 점 애니메이션 타이머 (0.5초마다 갱신)
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (_isLocating && mounted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
        });
      }
    });
  }

  Future<void> _updateW3WDisplay() async {
    if (!mounted) return;
    setState(() {
      _isLocating = true;
      _currentW3W = "위치 수신 중";
    });
    String words = await _getW3WAddress();
    if (mounted) {
      setState(() {
        _isLocating = false;
        _currentW3W = words;
      });
    }
  }

  Future<String> _getW3WAddress() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return "GPS 꺼짐";
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 25),
      );
      final url = "https://api.what3words.com/v3/convert-to-3wa?coordinates=${pos.latitude},${pos.longitude}&key=$w3wApiKey&language=ko";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return "///${json.decode(response.body)['words']}";
      }
    } catch (e) {
      try {
        Position? lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          final url = "https://api.what3words.com/v3/convert-to-3wa?coordinates=${lastPos.latitude},${lastPos.longitude}&key=$w3wApiKey&language=ko";
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200) return "///${json.decode(res.body)['words']}(지연)";
        }
      } catch (_) {}
    }
    return "위치 확인 불가";
  }

  @override
  void dispose() { 
    _timer?.cancel(); 
    _dotTimer?.cancel();
    _controller.dispose(); 
    super.dispose(); 
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null) return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int targetMin = _selectedHours == 0 ? 5 : _selectedHours * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= targetMin) {
      List contacts = json.decode(contactsJson);
      String w3wAddress = await _getW3WAddress();
      for (var c in contacts) {
        if (c['number'] != null) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심지키미] 응답 없음!\n마지막 확인: $last\n위치: $w3wAddress",
          );
        }
      }
      _updateCheckIn();
    }
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
    _updateW3WDisplay();
  }

  @override
  Widget build(BuildContext context) {
    String displayW3W = _isLocating ? "$_currentW3W${'.' * _dotCount}" : _currentW3W;

    return Scaffold(
      appBar: AppBar(
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
        toolbarHeight: 45,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            width: double.infinity,
            color: Colors.orange.withOpacity(0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                const SizedBox(width: 6),
                Flexible(child: Text(displayW3W, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 12)),
              selected: _selectedHours == h,
              onSelected: (v) async {
                setState(() => _selectedHours = h);
                (await SharedPreferences.getInstance()).setInt('selectedHours', h);
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 11)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
          GestureDetector(
            onTapDown: (_) => _controller.forward(),
            onTapUp: (_) { _controller.reverse(); _updateCheckIn(); },
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 160, height: 160,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
                child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.favorite, size: 60, color: Colors.orange))),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Text("미응답 시 보호자에게 세 단어 주소가 전송됩니다.", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ),
          const SizedBox(height: 20),
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
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontSize: 16)), backgroundColor: const Color(0xFFFFF3E0), toolbarHeight: 45),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 14)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 12)),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(15),
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
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                  child: const Text("보호자 연락처 추가", style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    await [Permission.contacts, Permission.sms, Permission.location].request();
                    await Permission.locationAlways.request();
                    if (mounted) openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40), backgroundColor: Colors.orangeAccent, foregroundColor: Colors.white),
                  child: const Text("앱 권한 설정", style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
