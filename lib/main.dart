import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
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
  final Telephony telephony = Telephony.instance;
  String _lastCheckIn = "기록 없음";
  String _emergencyContact = "미설정";
  String _contactName = "보호자";
  bool _isWinking = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요!";
      _emergencyContact = prefs.getString('emergencyNumber') ?? "미설정";
      _contactName = prefs.getString('emergencyName') ?? "보호자";
    });
  }

  // 화면 이동 없이 즉시 문자를 보내는 도전형 핵심 기능
  Future<void> _sendDirectSMS() async {
    if (_emergencyContact == "미설정") {
      _showSnackBar("먼저 보호자 연락처를 설정해주세요.");
      return;
    }

    bool? permissionsGranted = await telephony.requestSmsPermissions;
    if (permissionsGranted == true) {
      try {
        await telephony.sendSms(
          to: _emergencyContact,
          message: "[하루 안부 지킴이] 사용자의 안부 확인이 지연되고 있습니다. 확인 부탁드립니다.",
        );
        _showSnackBar("보호자에게 안부 문자를 자동 발송했습니다.");
      } catch (e) {
        _showSnackBar("발송 실패: $e");
      }
    } else {
      _showSnackBar("문자 발송 권한이 거부되었습니다.");
    }
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isWinking = true);
    
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isWinking = false;
          _lastCheckIn = now;
        });
        _showSnackBar("안부가 확인되었습니다. 좋은 하루 되세요!");
      }
    });
  }

  Future<void> _pickContact() async {
    if (await Permission.contacts.request().isGranted) {
      try {
        final Contact? contact = await ContactsService.openDeviceContactPicker();
        if (contact != null && contact.phones!.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          String name = contact.displayName ?? "보호자";
          String number = contact.phones!.first.value ?? "";
          await prefs.setString('emergencyName', name);
          await prefs.setString('emergencyNumber', number);
          setState(() {
            _contactName = name;
            _emergencyContact = number;
          });
        }
      } catch (e) {
        debugPrint("오류: $e");
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("최근 안부 확인 시간", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 5),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: CircleAvatar(
                  radius: 90,
                  backgroundColor: Colors.yellow[400],
                  child: Icon(
                    _isWinking ? Icons.face_retouching_natural : Icons.sentiment_very_satisfied_rounded,
                    size: 100,
                    color: Colors.brown[700],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
            ElevatedButton.icon(
              onPressed: _sendDirectSMS,
              icon: const Icon(Icons.send),
              label: const Text("자동 문자 발송 테스트"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[50],
                foregroundColor: Colors.orange[900],
              ),
            ),
            const SizedBox(height: 30),
            Text("보호자: $_contactName", style: const TextStyle(fontSize: 16)),
            TextButton(onPressed: _pickContact, child: const Text("연락처 설정 변경")),
          ],
        ),
      ),
    );
  }
}
