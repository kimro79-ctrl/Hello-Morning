import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

// 백그라운드 작업 식별자
const taskName = "safetyCheckTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimeStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts');

    if (lastTimeStr != null && contactJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      // [테스트] 5분 이상 경과 시 발송
      if (DateTime.now().difference(lastTime).inMinutes >= 5) {
        List<dynamic> decoded = json.decode(contactJson);
        List<String> numbers = decoded.map((item) => item['number'].toString()).toList();
        
        if (numbers.isNotEmpty) {
          try {
            // sendDirect: true가 핵심 (안드로이드 전용)
            await sendSMS(
              message: "[지킴이 테스트] 5분간 안부 확인이 없어 자동 발송되었습니다.",
              recipients: numbers,
              sendDirect: true,
            );
          } catch (e) {
            debugPrint("자동발송 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 백그라운드 서비스 초기화
  await Workmanager().initialize(callbackDispatcher);
  // 15분마다 시스템이 깨어나서 5분 지났는지 확인 (안드로이드 최소 주기)
  await Workmanager().registerPeriodicTask(
    "1",
    taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.not_required),
  );

  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        useMaterial3: true,
      ),
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(_controller);
  }

  Future<void> _requestPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.ignoreBatteryOptimizations].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "스위치를 눌러주세요";
      String? contactJson = prefs.getString('contacts');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);
    
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    setState(() {
      _lastCheckIn = now;
      Timer(const Duration(seconds: 1), () => _isPressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("안부 지킴이 (5분 테스트)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.redAccent,
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          
          // 누르면 레드 컬러 피드백이 오는 스위치
          GestureDetector(
            onTap: _checkIn,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isPressed ? Colors.red[100] : Colors.white,
                  boxShadow: [
                    BoxShadow(color: _isPressed ? Colors.red.withOpacity(0.3) : Colors.black12, blurRadius: 20, offset: const Offset(10, 10)),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipOval(child: Image.asset('assets/smile.png', width: 140)),
                      const SizedBox(height: 5),
                      Text("CLICK", style: TextStyle(color: _isPressed ? Colors.red : Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const Text("5분간 미확인 시 등록된 번호로 자동 발송", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
