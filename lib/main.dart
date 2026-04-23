import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:async';

void main() => runApp(const HelloMorningApp());

class HelloMorningApp extends StatelessWidget {
  const HelloMorningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '헬로 모닝',
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
  String _lastCheckIn = "아직 기록이 없습니다";
  String _emergencyContact = "설정되지 않음";
  String _contactName = "보호자";
  bool _isWinking = false;

  // 애니메이션을 위한 컨트롤러
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();

    // 애니메이션 설정 (누를 때 커졌다 작아지는 효과)
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
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘 첫 미소를 지어주세요!";
      _emergencyContact = prefs.getString('emergencyNumber') ?? "설정되지 않음";
      _contactName = prefs.getString('emergencyName') ?? "보호자";
    });
  }

  Future<void> _checkIn() async {
    // 애니메이션 실행
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
            content: const Text("오늘도 멋진 하루 보내세요!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.yellow[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        debugPrint("연락처 선택 오류: $e");
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("연락처 접근 권한이 필요합니다.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("헬로 모닝", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
        centerTitle: true,
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("최근 미소 기록", style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            
            // 애니메이션이 적용된 버튼
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 15,
                        spreadRadius: 5,
                      )
                    ],
                  ),
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
            ),
            
            const SizedBox(height: 60),
            Card(
              elevation: 0,
              color: Colors.orange[50],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
                child: Column(
                  children: [
                    const Text("비상 연락처", style: TextStyle(color: Colors.orange)),
                    const SizedBox(height: 5),
                    Text("$_contactName : $_emergencyContact", 
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _pickContact,
              icon: const Icon(Icons.contact_phone),
              label: const Text("연락처 변경하기"),
              style: TextButton.styleFrom(foregroundColor: Colors.orange[800]),
            ),
          ],
        ),
      ),
    );
  }
}
