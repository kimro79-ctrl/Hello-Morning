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
  String _currentLocationText = "위치 확인 중"; 
  int _selectedHours = 1; 
  Timer? _timer;
  Timer? _dotTimer;
  int _dotCount = 0;
  bool _isLocating = false;
  bool _isPressed = false;

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
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (_isLocating && mounted) {
        setState(() { _dotCount = (_dotCount + 1) % 4; });
      }
    });
    debugPrint("🚀 앱 시작: 타이머 가동 중 (5분 주기)");
  }

  Future<void> _updateLocationDisplay() async {
    if (!mounted) return;
    setState(() { _isLocating = true; _currentLocationText = "위치 수신 중"; });
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted) {
        setState(() {
          _isLocating = false;
          _currentLocationText = "좌표: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";
        });
        debugPrint("📍 위치 갱신 성공: ${position.latitude}, ${position.longitude}");
      }
    } catch (e) {
      if (mounted) setState(() { _isLocating = false; _currentLocationText = "위치 확인 불가"; });
      debugPrint("❌ 위치 수신 에러: $e");
    }
  }

  Future<void> _checkAndSendSms() async {
    debugPrint("🔍 [체크] 발송 조건 확인 시작...");
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    
    if (last == null) {
      debugPrint("⚠️ 경고: 체크인 기록이 없어 발송을 건너뜁니다.");
      return;
    }
    if (contactsJson == null || contactsJson == "[]") {
      debugPrint("⚠️ 경고: 등록된 보호자 연락처가 없습니다.");
      return;
    }
    
    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int targetMin = _selectedHours == 0 ? 5 : _selectedHours * 60;
    int diff = DateTime.now().difference(lastTime).inMinutes;
    
    debugPrint("⏳ 경과 시간: $diff분 / 설정 시간: $targetMin분");

    if (diff >= targetMin) {
      debugPrint("🚨 조건 충족! 문자 발송 절차 진입");
      List contacts = json.decode(contactsJson);
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      String mapLink = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
      
      String messageBody = "[안심지키미] 응답 없음!\n마지막 확인: $last\n위치: $mapLink";
      
      for (var c in contacts) {
        if (c['number'] != null) {
          String cleanNumber = c['number'].replaceAll(RegExp(r'[^0-9]'), '');
          debugPrint("📩 전송 시도 -> 대상: ${c['name']}($cleanNumber)");
          try {
            await BackgroundSms.sendMessage(
              phoneNumber: cleanNumber, 
              message: messageBody,
            );
            debugPrint("✅ 전송 명령 완료");
          } catch (e) {
            debugPrint("❌ 전송 실패 에러: $e");
          }
        }
      }
      _updateCheckIn();
    } else {
      debugPrint("😴 아직 시간이 되지 않았습니다.");
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

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
    _updateLocationDisplay();
    debugPrint("✅ 체크인 갱신 시각: $now");
  }

  @override
  Widget build(BuildContext context) {
    String displayText = _isLocating ? "$_currentLocationText${'.' * _dotCount}" : _currentLocationText;
    return Scaffold(
      appBar: AppBar(
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
            width: double.infinity,
            color: Colors.orange.withOpacity(0.06),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                const SizedBox(width: 5),
                Flexible(child: Text(displayText, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "$h시간", style: const TextStyle(fontSize: 12)),
              selected: _selectedHours == h,
              onSelected: (v) async {
                setState(() => _selectedHours = h);
                (await SharedPreferences.getInstance()).setInt('selectedHours', h);
                debugPrint("⚙️ 시간 설정 변경: $h시간");
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 확인 시각", style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 4),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          GestureDetector(
            onTapDown: (_) { setState(() => _isPressed = true); _controller.forward(); },
            onTapUp: (_) { 
              setState(() => _isPressed = false); 
              _controller.reverse(); 
              _updateCheckIn(); 
              debugPrint("👆 사용자가 생존 신고 버튼을 눌렀습니다.");
            },
            onTapCancel: () => setState(() { _isPressed = false; _controller.reverse(); }),
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
                  border: Border.all(
                    color: _isPressed ? const Color(0xFFFFC1CC) : Colors.transparent, 
                    width: 4,
                  ),
                ),
                child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.favorite, size: 80, color: Colors.orange))),
              ),
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 25),
            child: Text("미응답 시 보호자에게 위치가 전송됩니다.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
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
      appBar: AppBar(title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), backgroundColor: const Color(0xFFFFF3E0)),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 14)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 13)),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
                debugPrint("🗑 연락처 삭제됨");
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
                        debugPrint("➕ 연락처 추가 성공: ${c.displayName}");
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text("보호자 추가", style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    debugPrint("🔐 권한 요청 및 설정창 이동 시도");
                    await [Permission.sms, Permission.location, Permission.contacts].request();
                    await Permission.locationAlways.request();
                    if (mounted) openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45), backgroundColor: Colors.orangeAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
