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
          directSms.sendSms(
            message: "[안부 지킴이] 5분간 확인이 없어 자동 발송된 메시지입니다.",
            address: number,
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
  
  // 15분마다 깨어나서 5분 경과 여부 확인
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
      theme: ThemeData(primarySwatch: Colors.orange, useMaterial3: true),
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
    await [Permission.sms, Permission.contacts, Permission.ignoreBatteryOptimizations].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요";
      String? contactJson = prefs.getString('contacts');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _checkIn() async {
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
  }

  // UI 구성 (기존 디자인 유지)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("하루 안부 지킴이"), backgroundColor: Colors.orangeAccent),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("마지막 확인: $_lastCheckIn"),
            const SizedBox(height: 50),
            GestureDetector(
              onTap: _checkIn,
              child: CircleAvatar(
                radius: 80,
                backgroundColor: Colors.yellow[200],
                child: ClipOval(child: Image.asset('assets/smile.png', width: 120)),
              ),
            ),
            const SizedBox(height: 20),
            const Text("5분 미확인 시 자동 문자 발송 테스트 중"),
          ],
        ),
      ),
    );
  }
}
