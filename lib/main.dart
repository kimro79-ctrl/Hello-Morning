import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; // 문자 발송을 위해 필요
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

  // 문자를 보내는 핵심 기능
  Future<void> _sendEmergencySMS() async {
    if (_emergencyContact == "미설정") return;
    
    // 문자 메시지 내용 (한글)
    final String message = "안녕하세요, '하루 안부 지킴이'입니다. $_contactName님께 등록된 사용자의 안부 확인이 지연되고 있습니다. 확인 부탁드립니다.";
    final Uri smsUri = Uri.parse('sms:$_emergencyContact?body=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("문자 앱을 열 수 없습니다.")),
        );
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("안부가 확인되었습니다!", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.yellow[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
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
            Text("마지막 확인: $_lastCheckIn"),
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
            // 수동으로 안부 문자를 보낼 수 있는 비상 버튼 (테스트용)
            if (_emergencyContact != "미설정")
              ElevatedButton.icon(
                onPressed: _sendEmergencySMS,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text("지금 바로 안부 문자 보내기"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red),
              ),
            const SizedBox(height: 20),
            Text("보호자: $_contactName ($_emergencyContact)"),
            TextButton(onPressed: _pickContact, child: const Text("연락처 설정")),
          ],
        ),
      ),
    );
  }
}
