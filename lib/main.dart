import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase 초기화 실패: $e");
  }

  // 필수 권한 요청 (SMS는 서버 발송이므로 위치/연락처 집중)
  await [
    Permission.contacts,
    Permission.location,
    Permission.notification,
  ].request();
  
  if (await Permission.location.isGranted) {
    await Permission.locationAlways.request();
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
  int _idx = 0;
  final List<Widget> _pages = [const HomeScreen(), const SettingScreen()];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx, selectedFontSize: 10, unselectedFontSize: 10,
      onTap: (i) => setState(() => _idx = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 20), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings, size: 20), label: '설정'),
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
  int _hrs = 1;
  bool _down = false;
  String _uid = "";

  @override
  void initState() { 
    super.initState(); 
    _initUserId(); 
  }

  void _initUserId() async {
    var deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      var androidInfo = await deviceInfo.androidInfo;
      _uid = androidInfo.id;
    } else if (Platform.isIOS) {
      var iosInfo = await deviceInfo.iosInfo;
      _uid = iosInfo.identifierForVendor ?? "unknown_user";
    }
    _listenToFirebase();
  }

  void _listenToFirebase() {
    if (_uid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (snap.exists) {
        setState(() {
          _last = snap.data()?['lastCheckIn'] ?? "기록 없음";
          _hrs = snap.data()?['selectedHours'] ?? 1;
        });
      }
    });
  }

  void _checkIn() async {
    if (_uid.isEmpty) return;
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8)
      );
    } catch (_) {}

    // 서버에 판단 근거 전송 및 알람 이력 초기화
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'lastCheckIn': now,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastLocation': pos != null ? "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}" : "위치확인불가",
      'autoSmsEnabled': true,
      'lastAlertSent': null, // ✅ 체크인 시 알람 발송 기록 초기화 (중복 방지 해제)
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        const SizedBox(height: 15),
        const Text("1인가구 안심 지키미", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 15),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "${h}h", style: const TextStyle(fontSize: 10)),
              selected: _hrs == h,
              onSelected: (v) async {
                setState(() => _hrs = h);
                await FirebaseFirestore.instance.collection('users').doc(_uid).update({'selectedHours': h});
              },
            )).toList(),
          ),
        ),
        const Spacer(),
        Text("마지막 확인: $_last", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
        const SizedBox(height: 15),
        GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) { setState(() => _down = false); _checkIn(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _down ? 135 : 145, height: _down ? 135 : 145,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: ClipOval(
              child: Image.asset(
                'assets/smile.png',
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.face_retouching_natural, size: 70, color: Colors.orangeAccent),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        const Text("매일 한 번 버튼을 눌러주세요", style: TextStyle(fontSize: 11, color: Colors.grey)),
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
    if (Platform.isAndroid) {
      _uid = (await deviceInfo.androidInfo).id;
    } else if (Platform.isIOS) {
      _uid = (await deviceInfo.iosInfo).identifierForVendor ?? "unknown";
    }
    _loadSettings();
  }
  
  void _loadSettings() {
    FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      if (snap.exists) {
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
        Container(
          width: double.infinity, margin: const EdgeInsets.all(10), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFE0B2), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orangeAccent)),
          child: const Text("서버 감시 모드: 폰이 꺼져 있어도 서버에서 시간을 계산하여 문자를 발송합니다.", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            title: const Text("서버 자동 감시 활성화", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: const Text("미응답 시 보호자에게 자동 알림", style: TextStyle(fontSize: 10)),
            trailing: Transform.scale(
              scale: 1.3,
              child: Switch(
                value: _on,
                activeColor: Colors.orange,
                onChanged: (v) async {
                  await FirebaseFirestore.instance.collection('users').doc(_uid).update({'autoSmsEnabled': v});
                },
              ),
            ),
          ),
        ),
        const Divider(height: 20),
        Expanded(
          child: ListView.builder(
            itemCount: _list.length,
            itemBuilder: (c, i) => ListTile(
              dense: true,
              leading: const Icon(Icons.person, size: 18),
              title: Text(_list[i]['name'] ?? "이름 없음", style: const TextStyle(fontSize: 12)),
              subtitle: Text(_list[i]['number'] ?? "", style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent), onPressed: () async {
                _list.removeAt(i);
                await FirebaseFirestore.instance.collection('users').doc(_uid).update({'contacts': _list});
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15),
          child: SizedBox(width: double.infinity, height: 42, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5C6BC0), foregroundColor: Colors.white),
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
            child: const Text("보호자 등록", style: TextStyle(fontSize: 12)),
          )),
        ),
      ],
    ),
  );
}
