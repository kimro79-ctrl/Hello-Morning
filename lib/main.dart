import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';
import 'package:direct_sms/direct_sms.dart';
import 'dart:async';
import 'dart:convert';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimeStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts');

    if (lastTimeStr != null && contactJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      // [테스트] 5분 이상 경과 시 자동 발송
      if (DateTime.now().difference(lastTime).inMinutes >= 5) {
        List<dynamic> decoded = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        
        for (var item in decoded) {
          String number = item['number'].toString();
          // 에러 해결: 'address'를 'phone'으로 변경
          directSms.sendSms(
            message: "[안부 지킴이] 5분간 확인이 없어 자동 발송되었습니다.",
            phone: number, 
          );
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  
  await Workmanager().registerPeriodicTask(
    "safety_check",
    "checkTask",
    frequency: const Duration(minutes: 15),
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
        primarySwatch: Colors.orange,
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

class _MainScreenState extends State<MainScreen> {
  String _lastCheckIn = "기록 없음";
  List<Map<String, String>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // 필수 권한 요청
    await [
      Permission.sms,
      Permission.contacts,
      Permission.ignoreBatteryOptimizations
    ].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요";
      String? contactJson = prefs.getString('contacts');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(
            json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _checkIn() async {
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 5),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            GestureDetector(
              onTap: _checkIn,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor: Colors.yellow[200],
                  child: ClipOval(
                    // 이미지가 없을 경우를 대비해 아이콘으로 대체 가능하도록 설정
                    child: Image.asset(
                      'assets/smile.png', 
                      width: 120,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.sentiment_satisfied_alt, size: 100, color: Colors.orange),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Text("5분 미확인 시 등록된 보호자에게", style: TextStyle(color: Colors.redAccent)),
            const Text("자동으로 문자가 전송됩니다.", style: TextStyle(color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }
}
