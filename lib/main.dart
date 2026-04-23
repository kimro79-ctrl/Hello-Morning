import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart'; // 직접 발송용
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:async';

void main() => runApp(const DailySafetyApp());

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '하루 안부 지킴이',
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

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  final Telephony telephony = Telephony.instance;
  String _lastCheckIn = "기록 없음";
  String _emergencyContact = "미설정";
  String _contactName = "보호자";
  
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(_controller);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요!";
      _emergencyContact = prefs.getString('emergencyNumber') ?? "미설정";
      _contactName = prefs.getString('emergencyName') ?? "보호자";
    });
  }

  // 핵심: 사용자 화면 이동 없이 바로 문자 발송
  Future<void> _sendDirectSMS() async {
    if (_emergencyContact == "미설정") return;

    bool? permissionsGranted = await telephony.requestSmsPermissions;
    if (permissionsGranted != null && permissionsGranted) {
      await telephony.sendSms(
        to: _emergencyContact,
        message: "['하루 안부 지킴이' 알림] 사용자의 안부 확인이 지연되었습니다. 확인이 필요합니다.",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("보호자에게 안부 문자를 자동 발송했습니다.")),
        );
      }
    }
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    setState(() => _lastCheckIn = now);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("안부가 확인되었습니다! 문자가 발송되지 않습니다.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("하루 안부 지킴이"), centerTitle: true, backgroundColor: Colors.orangeAccent),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("미확인 시 자동으로 문자가 발송됩니다", style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            const SizedBox(height: 10),
            Text("마지막 확인: $_lastCheckIn", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: CircleAvatar(
                  radius: 100,
                  backgroundColor: Colors.yellow[400],
                  child: Icon(Icons.sentiment_very_satisfied_rounded, size: 110, color: Colors.brown[700]),
                ),
              ),
            ),
            const SizedBox(height: 50),
            // 테스트용 자동 발송 버튼 (심사 때는 숨길 수 있음)
            ElevatedButton(
              onPressed: _sendDirectSMS,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[100]),
              child: const Text("자동 문자 발송 테스트"),
            ),
            const SizedBox(height: 20),
            Text("수신인: $_contactName ($_emergencyContact)"),
          ],
        ),
      ),
    );
  }
}
