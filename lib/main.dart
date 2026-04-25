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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  String _currentW3W = "위치 권한을 설정해주세요";
  int _selectedHours = 1; 
  Timer? _timer;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  // what3words API 키 (https://developer.what3words.com/ 에서 발급)
  final String w3wApiKey = "YOUR_W3W_API_KEY"; 

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
    _loadData();
    _checkLocationPermission(); // 앱 시작 시 위치 권한 체크
    _timer = Timer.periodic(const Duration(minutes: 1), (t) => _checkAndSendSms());
  }

  // 위치 권한 상태를 확인하고 UI에 반영하는 함수
  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _currentW3W = "GPS가 꺼져 있습니다");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      _updateW3WDisplay();
    } else {
      setState(() => _currentW3W = "위치 권한 허용 필요");
    }
  }

  Future<void> _updateW3WDisplay() async {
    String words = await _getW3WAddress();
    if (mounted) setState(() => _currentW3W = words);
  }

  Future<String> _getW3WAddress() async {
    try {
      // 위치 권한 체크를 먼저 수행하여 에러 방지
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return "권한 없음";
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5)
      );
      
      final url = "https://api.what3words.com/v3/convert-to-3wa?coordinates=${pos.latitude},${pos.longitude}&key=$w3wApiKey&language=ko";
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return "///${data['words']}";
      }
    } catch (e) {
      return "위치 수신 대기 중...";
    }
    return "위치 정보 없음";
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

  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null) return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int diffInMin = DateTime.now().difference(lastTime).inMinutes;
    int targetMin = _selectedHours == 0 ? 5 : _selectedHours * 60;

    if (diffInMin >= targetMin) {
      List contacts = json.decode(contactsJson);
      String w3wAddress = await _getW3WAddress();
      
      for (var c in contacts) {
        await BackgroundSms.sendMessage(
          phoneNumber: c['number'],
          message: "[안심지키미] 응답 없음!\n마지막 확인: $last\n현재 위치(W3W): $w3wAddress",
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
    _checkLocationPermission(); // 버튼 누를 때마다 권한 확인 및 주소 갱신
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            color: Colors.orange.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, color: Colors.redAccent, size: 16),
                const SizedBox(width: 8),
                Text("현재 위치: $_currentW3W", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
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
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          GestureDetector(
            onTapDown: (_) => _controller.forward(),
            onTapUp: (_) { _controller.reverse(); _updateCheckIn(); },
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 220, height: 220,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
                child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.favorite, size: 100, color: Colors.orange))),
              ),
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            child: Text("응답이 없으면 보호자에게 '세 단어 주소'가 발송됩니다.", textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
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
  List _contacts = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _contacts = json.decode(p.getString('contacts_list') ?? "[]"));
  }

  // 가장 강력한 권한 요청 로직
  Future<void> _requestPermissions() async {
    // 1. 기본 권한들 요청
    await [Permission.contacts, Permission.sms, Permission.location].request();
    
    // 2. 백그라운드 위치 권한 (안드로이드 10+)
    var status = await Permission.locationAlways.request();
    
    // 3. 배터리 최적화 제외 (앱 꺼짐 방지)
    await Permission.ignoreBatteryOptimizations.request();

    if (status.isDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("위치 권한 필수 설정"),
            content: const Text("앱이 백그라운드에서도 위치를 찾으려면\n'설정 > 권한 > 위치'에서\n'항상 허용'으로 직접 바꿔주셔야 합니다."),
            actions: [
              TextButton(onPressed: () => openAppSettings(), child: const Text("설정하러 가기")),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인")),
            ],
          ),
        );
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("권한 설정이 완료되었습니다.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 및 권한 설정"), backgroundColor: const Color(0xFFFFF3E0)),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
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
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: const Text("보호자 연락처 추가"),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.orangeAccent, foregroundColor: Colors.white),
                  child: const Text("백그라운드 & 위치 권한 설정"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
