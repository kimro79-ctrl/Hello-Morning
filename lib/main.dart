import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:telephony/telephony.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckInStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts_list');
    
    if (lastCheckInStr != null && contactJson != null) {
      DateTime lastCheck = DateFormat('yyyy-MM-dd HH:mm').parse(lastCheckInStr);
      int diff = DateTime.now().difference(lastCheck).inMinutes;

      if (diff >= 5) {
        List<dynamic> contacts = json.decode(contactJson);
        final Telephony telephony = Telephony.instance;
        for (var c in contacts) {
          try {
            await telephony.sendSms(
              to: c['number'],
              message: "[하루 안부 지키미] 5분간 안부가 확인되지 않아 자동 발송되었습니다.",
            );
          } catch (e) {
            debugPrint("SMS 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MainNavigation(),
  ));
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const ContactScreen(), const SettingScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF9FA8DA),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '연락처'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  bool _isPressed = false;

  @override
  void initState() { super.initState(); _loadData(); }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해주세요"; });
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);

    // 1초 뒤에 레드 테두리 해제
    Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = now; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("하루 안부 지키미", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFB39DDB),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("마지막 확인 시간", style: TextStyle(color: Color(0xFF98A6D4), fontSize: 13)),
          const SizedBox(height: 10),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, color: Color(0xFFE59A59), fontWeight: FontWeight.w500)),
          const SizedBox(height: 60),
          
          // 입체 원형 스위치 버튼
          Center(
            child: GestureDetector(
              onTap: _onCheckIn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF8F9FD),
                  // 눌렸을 때 연한 레드 테두리 적용
                  border: Border.all(
                    color: _isPressed ? Colors.red[200]! : Colors.white, 
                    width: 8
                  ),
                  boxShadow: _isPressed 
                    ? [ // 눌렸을 때 (안으로 들어간 느낌)
                        BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4, spreadRadius: 1.0),
                        const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4, spreadRadius: 1.0),
                      ]
                    : [ // 평소 (튀어나온 느낌)
                        BoxShadow(color: Colors.black.withOpacity(0.08), offset: const Offset(10, 10), blurRadius: 20),
                        const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                      ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 이미지 (assets 폴더에 smile.png가 있어야 함)
                    Image.asset('assets/smile.png', width: 160),
                    // 이미지 중앙 하단 CLICK 텍스트
                    Positioned(
                      bottom: 30,
                      child: Text(
                        "CLICK", 
                        style: TextStyle(fontSize: 11, color: Colors.grey[350]!, fontWeight: FontWeight.bold, letterSpacing: 2)
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 60),
          const Text("5분 미확인 시 자동 발송 모드", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      ),
    );
  }
}

// 연락처/설정 화면은 이전과 동일하게 유지...
class ContactScreen extends StatelessWidget { const ContactScreen({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("연락처 화면"))); }
class SettingScreen extends StatelessWidget { const SettingScreen({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("설정 화면"))); }
