import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<void> _sendEmergencySMS() async {
    if (_emergencyContact == "미설정") return;
    
    final String message = "[하루 안부 지킴이] 사용자의 안부 확인이 지연되었습니다.";
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
          const SnackBar(
            content: Text("안부가 확인되었습니다!", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.orangeAccent,
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
                  radius: 110, // 이미지가 크니까 지름을 조금 키웁니다.
                  backgroundColor: Colors.yellow[400],
                  child: ClipOval(
                    child: Image.asset(
                      'assets/smile.png', // 우리가 등록한 이미지 경로
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover, // 원에 꽉 차게 조절
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
            if (_emergencyContact != "미설정")
              ElevatedButton.icon(
                onPressed: _sendEmergencySMS,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text("보호자에게 문자 보내기"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                ),
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
