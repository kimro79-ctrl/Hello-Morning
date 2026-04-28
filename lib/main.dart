import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:background_sms/background_sms.dart';
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
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _pages),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx,
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
  String _last = "기록 없음";
  String _gps = "대기 중";
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

  void _checkIn() async {
    if (_uid.isEmpty) return;
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    setState(() => _gps = "위치 수신 중...");
    
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8)
      );
      setState(() => _gps = "수신 완료");
    } catch (e) {
      setState(() => _gps = "수신 실패");
    }

    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'lastCheckIn': now,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastLocation': pos != null ? "${pos.latitude},${pos.longitude}" : "알수없음",
      'autoSmsEnabled': true,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        // ✅ 상단 UI: 파스텔 블루 그라데이션 + 작은 텍스트
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
          ),
          child: const Center(
            child: Text("1인가구 안심 지키미", 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          ),
        ),
        const SizedBox(height: 30),
        // ✅ 테두리에 연핑크가 들어간 시간 선택 섹션
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFFFCE4EC), width: 3), // 연핑크 테두리
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "${h}h"),
              selected: _hrs == h,
              selectedColor: const Color(0xFFFCE4EC),
              onSelected: (v) async {
                setState(() => _hrs = h);
                await FirebaseFirestore.instance.collection('users').doc(_uid).update({'selectedHours': h});
              },
            )).toList(),
          ),
        ),
        const Spacer(),
        Text("마지막 체크인: $_last", style: const TextStyle(fontSize: 15, color: Color(0xFF1A237E), fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text("GPS: $_gps", style: const TextStyle(fontSize: 11, color: Color(0xFF5C6BC0))),
        const SizedBox(height: 40),
        GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) { setState(() => _down = false); _checkIn(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _down ? 165 : 180, height: _down ? 165 : 180,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: ClipOval(
              child: Image.asset('assets/smile.png', fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.face, size: 80, color: Colors.orangeAccent)),
            ),
          ),
        ),
        const SizedBox(height: 30),
        const Text("오늘 하루도 무사히", style: TextStyle(fontSize: 13, color: Color(0xFF7986CB))),
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
        // ✅ 무료 문자 안내 배너
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(15),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(15)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("✔ 무료 문자 서비스 적용 완료", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              Text("기기 문자를 사용하므로 별도 비용이 들지 않습니다.", style: TextStyle(fontSize: 11, color: Color(0xFF1B5E20))),
            ],
          ),
        ),
        // ✅ [필수 설정] 직접 제어 섹션
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(" [필수 설정]", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFCE4EC), width: 2), // 연핑크 테두리
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("자동 안심 감시", style: TextStyle(fontWeight: FontWeight.bold)),
                        Switch(
                          value: _on,
                          activeColor: Colors.pinkAccent,
                          onChanged: (v) async {
                            if (v && !(await Permission.sms.isGranted)) { await Permission.sms.request(); }
                            await FirebaseFirestore.instance.collection('users').doc(_uid).update({'autoSmsEnabled': v});
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // ✅ 유저가 직접 버튼을 눌러 설정할 수 있는 버튼들
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton.icon(
                          onPressed: () => openAppSettings(),
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text("권한 설정"),
                        ),
                        TextButton.icon(
                          onPressed: () => Permission.ignoreBatteryOptimizations.request(),
                          icon: const Icon(Icons.battery_saver, size: 18),
                          label: const Text("배터리 최적화 제외"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [Icon(Icons.people, size: 18), SizedBox(width: 8), Text("보호자 목록")]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            itemCount: _list.length,
            itemBuilder: (c, i) => Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: ListTile(
                title: Text(_list[i]['name'] ?? "", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text(_list[i]['number'] ?? "", style: const TextStyle(fontSize: 12)),
                trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () async {
                  _list.removeAt(i);
                  await FirebaseFirestore.instance.collection('users').doc(_uid).update({'contacts': _list});
                }),
              ),
            ),
          ),
        ),
        // ✅ 보호자 등록 버튼 (기능 수정 완료)
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
              onPressed: () async {
                if (await Permission.contacts.request().isGranted) {
                  final contact = await ContactsService.openDeviceContactPicker();
                  if (contact != null) {
                    String phone = contact.phones?.isNotEmpty == true ? contact.phones!.first.value! : "";
                    if (phone.isNotEmpty) {
                      var data = {'name': contact.displayName, 'number': phone};
                      setState(() => _list.add(data));
                      await FirebaseFirestore.instance.collection('users').doc(_uid).update({'contacts': _list});
                    }
                  }
                }
              },
              child: const Text("보호자 등록하기"),
            ),
          ),
        ),
      ],
    ),
  );
}
