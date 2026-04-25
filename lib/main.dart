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
      selectedFontSize: 11,
      unselectedFontSize: 10,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 19), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 19), label: '설정'),
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
  bool _isPressed = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  // 사용자님의 실제 API 키
  final String w3wApiKey = "WTE21N79"; 

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
    _loadData();
    _updateW3WDisplay();
    _timer = Timer.periodic(const Duration(minutes: 1), (t) => _checkAndSendSms());
    
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (_isLocating && mounted) {
        setState(() { _dotCount = (_dotCount + 1) % 4; });
      }
    });
  }

  Future<void> _updateW3WDisplay() async {
    if (!mounted) return;
    setState(() { _isLocating = true; _currentW3W = "위치 수신 중"; });
    String words = await _getW3WAddress();
    if (mounted) setState(() { _isLocating = false; _currentW3W = words; });
  }

  Future<String> _getW3WAddress() async {
    try {
      // GPS 활성화 체크
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return "GPS 꺼짐";

      // 위치 좌표 수신 (전략 수정: 마지막 위치를 먼저 시도 후 현재 위치 요청)
      Position? pos = await Geolocator.getLastKnownPosition();
      
      // 마지막 위치가 없거나 너무 오래됐다면 새로 고침
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // 정확도 조절 (더 빨리 잡히게)
        timeLimit: const Duration(seconds: 10),
      );

      if (pos == null) return "위치 신호 없음";

      // what3words API 호출 (이 줄이 실행되어야 요청 카운트가 올라갑니다!)
      final url = "https://api.what3words.com/v3/convert-to-3wa?coordinates=${pos.latitude},${pos.longitude}&key=$w3wApiKey&language=ko";
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 7));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return "///${data['words']}";
      } else {
        return "API 응답 오류";
      }
    } catch (e) {
      return "위치 확인 실패";
    }
  }

  @override
  void dispose() { _timer?.cancel(); _dotTimer?.cancel(); _controller.dispose(); super.dispose(); }

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
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold, fontSize: 13)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
        toolbarHeight: 42,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
            width: double.infinity,
            color: Colors.orange.withOpacity(0.06),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, color: Colors.redAccent, size: 13),
                const SizedBox(width: 5),
                Flexible(child: Text(displayW3W, style: const TextStyle(fontSize: 9.5, color: Colors.black87, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 10)),
              selected: _selectedHours == h,
              onSelected: (v) async {
                setState(() => _selectedHours = h);
                (await SharedPreferences.getInstance()).setInt('selectedHours', h);
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 확인 시각", style: TextStyle(color: Colors.grey, fontSize: 9)),
          const SizedBox(height: 3),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
          GestureDetector(
            onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
            onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
            onTapCancel: () => setState(() { _isPressed = false; _controller.reverse(); }),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 145, height: 145,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  color: Colors.white, 
                  boxShadow: [
                    BoxShadow(
                      color: _isPressed ? const Color(0xFFFFC1CC) : Colors.black12, 
                      blurRadius: _isPressed ? 18 : 6,
                      spreadRadius: _isPressed ? 6 : 1,
                    )
                  ],
                  border: Border.all(
                    color: _isPressed ? const Color(0xFFFFC1CC) : Colors.transparent, 
                    width: 3,
                  ),
                ),
                child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.favorite, size: 50, color: Colors.orange))),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Text("미응답 시 보호자에게 위치가 전송됩니다.", textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, color: Colors.grey.shade400)),
          ),
          const SizedBox(height: 10),
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
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFFFF3E0), toolbarHeight: 42),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 11)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 9)),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 17), onPressed: () {
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
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("보호자 연락처 추가", style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    await [Permission.contacts, Permission.sms, Permission.location].request();
                    await Permission.locationAlways.request();
                    if (mounted) openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 42), backgroundColor: Colors.orangeAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("앱 권한 설정 열기", style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
