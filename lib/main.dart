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
        // 버튼의 그림자가 잘 보이도록 배경을 아주 연한 회색으로 설정
        scaffoldBackgroundColor: const Color(0xFFEFF0F3),
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
  bool _isPressed = false; // 버튼 눌림 상태 감지

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_controller);
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
    }
  }

  Future<void> _checkIn() async {
    // 1. 애니메이션 실행
    _controller.forward().then((_) => _controller.reverse());
    
    // 2. 상태 업데이트 (스위치 켜짐 효과)
    setState(() => _isPressed = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    // 3. 1.5초 후 스위치 색상 복구 (다시 누를 수 있는 상태)
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isPressed = false);
    });

    setState(() => _lastCheckIn = now);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("안부가 확인되었습니다!", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orangeAccent,
        duration: Duration(seconds: 1),
      ),
    );
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
        debugPrint("연락처 선택 오류: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("마지막 확인 시간", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 60),
            
            // --- 입체형 스위치 버튼 ---
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPressed ? Colors.orange[50] : const Color(0xFFEFF0F3),
                    boxShadow: _isPressed
                        ? [
                            // 눌렸을 때: 안으로 들어간 듯한 그림자
                            BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4, spreadRadius: 1),
                            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4, spreadRadius: 1),
                          ]
                        : [
                            // 평상시: 밖으로 튀어나온 듯한 그림자
                            BoxShadow(color: Colors.black.withOpacity(0.15), offset: const Offset(10, 10), blurRadius: 20),
                            const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                          ],
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isPressed ? Colors.orangeAccent : Colors.white.withOpacity(0.5),
                          width: 4,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 85,
                        backgroundColor: Colors.transparent,
                        child: ClipOval(
                          child: Image.asset(
                            'assets/smile.png',
                            width: 170,
                            height: 170,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ------------------------

            const SizedBox(height: 60),
            if (_emergencyContact != "미설정")
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Text("수신 보호자: $_contactName", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_emergencyContact, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _sendEmergencySMS,
                      icon: const Icon(Icons.mail_outline),
                      label: const Text("수동 문자 발송 테스트"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.redAccent,
                        elevation: 0,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _pickContact,
              child: const Text("보호자 연락처 설정 변경"),
            ),
          ],
        ),
      ),
    );
  }
}
