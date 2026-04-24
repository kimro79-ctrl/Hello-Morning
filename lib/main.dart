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

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  int _selectedMinutes = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // 1분마다 체크하여 설정 시간 경과 시 문자 발송
    _timer = Timer.periodic(const Duration(minutes: 1), (t) => _checkAndSendSms());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedMinutes = p.getInt('selectedMinutes') ?? 5;
    });
  }

  // 문자 발송 핵심 로직 보강
  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    
    if (last == null || contactsJson == null || last == "기록 없음") return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int diff = DateTime.now().difference(lastTime).inMinutes;

    if (diff >= _selectedMinutes) {
      try {
        // 위치 정보 가져오기 (타임아웃 설정으로 무한 대기 방지)
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        String mapUrl = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
        
        List contacts = json.decode(contactsJson);
        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심지키미] 응답 없음 감지!\n마지막 확인: $last\n위치: $mapUrl",
          );
        }
        // 문자 발송 후 체크인 시간 자동 갱신 (중복 발송 방지)
        _updateCheckIn();
      } catch (e) {
        // 위치를 못 가져와도 문자는 발송 시도
        List contacts = json.decode(contactsJson);
        for (var c in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['number'],
            message: "[안심지키미] 응답 없음!\n마지막 확인: $last\n(위치 정보 수신 실패)",
          );
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
        title: const Text("안심 지키미", style: TextStyle(color: Color(0xFFFF8A65), fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [5, 60, 720, 1440].map((m) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(m < 60 ? "$m분" : "${m ~/ 60}시간", style: const TextStyle(fontSize: 12)),
                selected: _selectedMinutes == m,
                selectedColor: const Color(0xFFFFCCBC),
                onSelected: (v) async {
                  setState(() => _selectedMinutes = m);
                  (await SharedPreferences.getInstance()).setInt('selectedMinutes', m);
                },
              ),
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 체크인 기록", style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF455A64))),
          const SizedBox(height: 30),
          GestureDetector(
            onTap: _updateCheckIn,
            child: Container(
              width: 220, height: 220,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
              child: ClipOval(child: Image.asset('assets/smile.png', fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.face, size: 80, color: Color(0xFFFFAB91)))),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(12)),
              child: Text("${_selectedMinutes >= 60 ? _selectedMinutes ~/ 60 : _selectedMinutes}${_selectedMinutes >= 60 ? '시간' : '분'} 미응답 시 문자가 발송됩니다.",
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 50),
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

  Future<void> _requestPermissions() async {
    await [Permission.contacts, Permission.sms, Permission.location, Permission.ignoreBatteryOptimizations].request();
    // 백그라운드 위치 권한은 별도로 요청해야 하는 경우가 많음
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("권한 설정을 완료했습니다.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 설정", style: TextStyle(fontSize: 15)), backgroundColor: const Color(0xFFFFF3E0), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: Text(_contacts[i]['number'], style: const TextStyle(fontSize: 12)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Color(0xFFE57373)), onPressed: () {
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE1F5FE), minimumSize: const Size(double.infinity, 50)),
                  child: const Text("보호자 추가", style: TextStyle(fontSize: 13, color: Color(0xFF0288D1))),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _requestPermissions,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8A65), minimumSize: const Size(double.infinity, 50)),
                  child: const Text("권한 전체 설정", style: TextStyle(fontSize: 13, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
