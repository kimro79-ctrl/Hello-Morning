import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:background_sms/background_sms.dart'; // ✅ 무료 문자 발송 패키지
import 'dart:async';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase 초기화 실패: $e");
  }
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      scaffoldBackgroundColor: const Color(0xFFFDFCF0),
      useMaterial3: true,
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
  int _idx = 0;
  final List<Widget> _pages = [const HomeScreen(), const SettingScreen()];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), () => _showStartGuide());
  }

  void _showStartGuide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("🛡️ 필수 설정 (문자 발송용)", 
          style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold)),
        content: const Text("비상시 문자를 무료로 발송하기 위해 아래 설정이 필수입니다.\n\n1. SMS 발송 권한 승인\n2. 배터리 최적화 제외 (중요)\n\n설정하지 않으면 문자가 차단될 수 있습니다."),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              // ✅ SMS 및 필수 권한 동시 요청
              await [
                Permission.sms,
                Permission.location,
                Permission.contacts,
                Permission.ignoreBatteryOptimizations, // 배터리 최적화 제외 요청
              ].request();
            },
            child: const Text("설정하러 가기"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx, selectedFontSize: 12, unselectedFontSize: 12,
      selectedItemColor: const Color(0xFF1A237E),
      onTap: (i) => setState(() => _idx = i),
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
  String _last = "확인 버튼을 눌러주세요";
  String _gps = "GPS 대기 중";
  int _hrs = 1;
  bool _down = false;
  String _uid = "";

  @override
  void initState() { super.initState(); _initUserId(); }

  void _initUserId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) { _uid = (await deviceInfo.androidInfo).id; }
    else { _uid = (await deviceInfo.iosInfo).identifierForVendor ?? "unknown"; }
    _listenToFirebase();
  }

  void _listenToFirebase() {
    if (_uid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _last = snap.data()?['lastCheckIn'] ?? "기록 없음";
          _hrs = snap.data()?['selectedHours'] ?? 1;
        });
      }
    });
  }

  // ✅ 기기에서 직접 무료 문자 발송 로직 (테스트용으로 즉시 발송 포함 가능)
  Future<void> _sendDirectSms(String msg) async {
    final snap = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    List contacts = snap.data()?['contacts'] ?? [];
    
    for (var person in contacts) {
      String number = person['number'] ?? "";
      if (number.isNotEmpty) {
        // 백그라운드 SMS 발송 시도
        SmsStatus result = await BackgroundSms.sendMessage(
          phoneNumber: number,
          message: msg,
        );
        debugPrint("문자 발송 결과: $result");
      }
    }
  }

  void _checkIn() async {
    if (_uid.isEmpty) return;
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    setState(() => _gps = "위치 갱신 중...");
    
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8)
      );
      setState(() => _gps = "위치 확인 완료");
    } catch (e) {
      setState(() => _gps = "위치 확인 실패");
    }

    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'lastCheckIn': now,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastLocation': pos != null ? "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}" : "위치불가",
      'autoSmsEnabled': true,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 30),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
          ),
          child: const Center(
            child: Text("HELLO MORNING", 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A237E), letterSpacing: 2.0)),
          ),
        ),
        const SizedBox(height: 40),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), 
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)]),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "${h}h"),
              selected: _hrs == h,
              selectedColor: const Color(0xFFBBDEFB),
              onSelected: (v) async {
                setState(() => _hrs = h);
                await FirebaseFirestore.instance.collection('users').doc(_uid).update({'selectedHours': h});
              },
            )).toList(),
          ),
        ),
        const Spacer(),
        Text("마지막 체크인: $_last", style: const TextStyle(fontSize: 16, color: Color(0xFF1A237E), fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("GPS 상태: $_gps", style: const TextStyle(fontSize: 12, color: Color(0xFF5C6BC0))),
        const SizedBox(height: 40),
        GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) { setState(() => _down = false); _checkIn(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _down ? 160 : 180, height: _down ? 160 : 180,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, 
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 20, spreadRadius: 10)]),
            child: ClipOval(
              child: Image.asset('assets/smile.png', fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.face, size: 90, color: Colors.orangeAccent)),
            ),
          ),
        ),
        const SizedBox(height: 30),
        const Text("오늘도 무사하신가요?", style: TextStyle(fontSize: 14, color: Color(0xFF7986CB), fontWeight: FontWeight.w500)),
        const Spacer(),
      ],
    ),
  );
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  List _list = [];
  bool _on = false;
  String _uid = "";

  @override
  void initState() { super.initState(); _initUserId(); }

  void _initUserId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) { _uid = (await deviceInfo.androidInfo).id; }
    else { _uid = (await deviceInfo.iosInfo).identifierForVendor ?? "unknown"; }
    _loadSettings();
  }
  
  void _loadSettings() {
    if (_uid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _list = snap.data()?['contacts'] ?? [];
          _on = snap.data()?['autoSmsEnabled'] ?? false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        // ✅ 안내 배너 (무료 발송 강조)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(15),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("✔ 무료 문자 발송 최적화 완료", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              SizedBox(height: 5),
              Text("별도의 서버 비용 없이 기기의 기본 문자를 사용합니다.\n'배터리 최적화 제외' 설정을 반드시 확인해주세요.", 
                style: TextStyle(fontSize: 11, color: Color(0xFF1B5E20), height: 1.5)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(" [필수 설정]", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), 
                  border: Border.all(color: Colors.pink.shade100, width: 2.5)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("자동 안심 감시", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                        Text("미응답 시 보호자에게 무료 문자 발송", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    Transform.scale(
                      scale: 1.6,
                      child: Switch(
                        value: _on,
                        activeColor: Colors.pinkAccent,
                        activeTrackColor: Colors.pink.shade50,
                        onChanged: (v) async {
                          if (v && !(await Permission.sms.isGranted)) {
                            await Permission.sms.request();
                          }
                          await FirebaseFirestore.instance.collection('users').doc(_uid).update({'autoSmsEnabled': v});
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Icon(Icons.people_alt, size: 18, color: Colors.blueGrey),
            SizedBox(width: 8),
            Text("알림 수신 보호자", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            itemCount: _list.length,
            itemBuilder: (c, i) => Card(
              elevation: 0, color: Colors.white, margin: const EdgeInsets.symmetric(vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                title: Text(_list[i]['name'] ?? "", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                subtitle: Text(_list[i]['number'] ?? "", style: const TextStyle(fontSize: 12)),
                trailing: IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: () async {
                  _list.removeAt(i);
                  await FirebaseFirestore.instance.collection('users').doc(_uid).update({'contacts': _list});
                }),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(25),
          child: SizedBox(width: double.infinity, height: 55, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text("보호자 등록하기", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            onPressed: () async {
              if (await Permission.contacts.request().isGranted) {
                final c = await ContactsService.openDeviceContactPicker();
                if (c != null) {
                  var newContact = {'name': c.displayName, 'number': c.phones?.isNotEmpty == true ? c.phones!.first.value : ""};
                  _list.add(newContact);
                  await FirebaseFirestore.instance.collection('users').doc(_uid).update({'contacts': _list});
                }
              }
            },
          )),
        ),
      ],
    ),
  );
}
