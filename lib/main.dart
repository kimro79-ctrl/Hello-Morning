import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

// --- 백그라운드 감시 로직 ---
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    String? lastTimeStr = prefs.getString('lastCheckIn');
    String? contactJson = prefs.getString('contacts');

    if (lastTimeStr != null && contactJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      DateTime now = DateTime.now();
      
      // [테스트 설정] 마지막 체크인으로부터 5분 이상 경과했는지 확인
      if (now.difference(lastTime).inMinutes >= 5) {
        List<Map<String, String>> contacts = List<Map<String, String>>.from(
            json.decode(contactJson).map((item) => Map<String, String>.from(item)));
        
        if (contacts.isNotEmpty) {
          List<String> recipients = contacts.map((c) => c['number']!).toList();
          String message = "[테스트] 안부 확인이 5분간 이뤄지지 않아 자동 발송되었습니다.";
          
          try {
            // sendDirect: true는 안드로이드에서 사용자 개입 없이 발송을 시도합니다.
            await sendSMS(message: message, recipients: recipients, sendDirect: true);
            print("자동 발송 성공");
          } catch (e) {
            print("자동 발송 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 백그라운드 초기화
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  
  // 15분마다 깨어나서 '5분이 지났는지' 검사하도록 예약
  await Workmanager().registerPeriodicTask(
    "safety_check_5min",
    "checkTask",
    frequency: const Duration(minutes: 15), 
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );

  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.red, useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  List<Map<String, String>> _contacts = [];
  bool _isPressed = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissions();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
  }

  // 필수 권한 요청 (SMS 전송 및 배터리 최적화 제외)
  Future<void> _requestPermissions() async {
    await [
      Permission.sms,
      Permission.contacts,
      Permission.ignoreBatteryOptimizations // 앱이 잠들지 않게 함
    ].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? contactJson = prefs.getString('contacts');
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "스위치를 눌러주세요!";
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(
            json.decode(contactJson).map((item) => Map<String, String>.from(item)));
      }
    });
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    Timer(const Duration(seconds: 1), () => setState(() => _isPressed = false));
    setState(() => _lastCheckIn = now);
  }

  // 연락처 추가 및 삭제 레이아웃은 이전과 동일하게 유지...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("5분 자동발송 테스트중", style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.redAccent,
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey)),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            
            // 레드 스위치
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 180, height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPressed ? Colors.red[50] : const Color(0xFFF0F0F0),
                    boxShadow: _isPressed ? [] : [
                      BoxShadow(color: Colors.black12, offset: const Offset(8, 8), blurRadius: 15),
                      const BoxShadow(color: Colors.white, offset: Offset(-8, -8), blurRadius: 15),
                    ],
                  ),
                  child: Center(
                    child: ClipOval(child: Image.asset('assets/smile.png', width: 140)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "테스트 안내: 마지막 클릭 후 5분이 지나면 시스템이 이를 감지하여 보호자에게 문자를 자동 발송합니다. (시스템 상황에 따라 최대 15분 소요)",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
