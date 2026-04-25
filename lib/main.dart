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

  // [수정된 위치 수신 로직]
  Future<String> _getW3WAddress() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return "GPS 꺼짐";

      // 1. 우선 기기에 저장된 마지막 위치가 있는지 확인 (매우 빠름)
      Position? pos = await Geolocator.getLastKnownPosition();

      // 2. 만약 저장된 위치가 없다면, 아주 낮은 정확도로 '강제' 수신 시도
      // 정확도를 low로 하면 GPS 위성 없이 와이파이/LTE 기지국 신호만으로 좌표를 바로 찍어줍니다.
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, 
        timeLimit: const Duration(seconds: 10),
      ).catchError((e) => throw Exception("위치 수신 타임아웃"));

      // 3. 좌표를 얻었다면 API 호출
      final url = "https://api.what3words.com/v3/convert-to-3wa?coordinates=${pos.latitude},${pos.longitude}&key=$w3wApiKey&language=ko";
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        return "///${json.decode(response.body)['words']}";
      }
    } catch (e) {
      debugPrint("에러 발생: $e");
    }
    return "위치 확인 불가";
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
          await BackgroundSms.sendMessage(phoneNumber: c['number'], message: "[안심지키미] 응답 없음!\n마지막 확인: $last\n위치: $w3wAddress");
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
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            width: double.infinity,
            color: Colors.orange.withOpacity(0.06),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                const SizedBox(width: 5),
                Flexible(child: Text(displayW3W, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(height: 15),
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
          const Text("마지막 확인 시각", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          GestureDetector(
            onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
            onTapUp: (_) { setState(() => _isPressed = false); _controller.reverse(); _updateCheckIn(); },
            onTapCancel: () => setState(() { _isPressed = false; _controller.reverse(); }),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 150, height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  color: Colors.white, 
                  boxShadow: [
                    BoxShadow(
                      color: _isPressed ? const Color(0xFFFFC1CC) : Colors.black12, 
                      blurRadius: _isPressed ? 20 : 7,
                      spreadRadius: _isPressed ? 7 : 1,
                    )
                  ],
                  border: Border.all(
                    color: _isPressed ? const Color(0xFFFFC1CC) : Colors.transparent, 
                    width: 3.5,
                  ),
                ),
                child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.favorite, size: 55, color: Colors.orange))),
              ),
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 25),
            child: Text("미응답 시 보호자에게 위치가 전송됩니다.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFFFF3E0)),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () {
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
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("보호자 추가"),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    await [Permission.contacts, Permission.sms, Permission.location].request();
                    await Permission.locationAlways.request();
                    if (mounted) openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.orangeAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("앱 권한 설정"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
