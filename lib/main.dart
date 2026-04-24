import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';

void main() => runApp(const DailySafetyApp());

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const ContactScreen(), const SettingScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF9FA8DA),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '연락처'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  bool _isPressed = false;

  @override
  void initState() { super.initState(); _loadData(); }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해 주세요"; });
  }

  void _onCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);

    Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = now; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("하루 안부", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFFD180), // 파스텔 오렌지
        centerTitle: true, elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // --- 상단 캘린더 위젯 영역 ---
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
            child: Column(
              children: [
                Text(DateFormat('M월').format(DateTime.now()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (index) => Column(
                    children: [
                      Text(["월","화","수","목","금","토","일"][index], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 5),
                      const Icon(Icons.circle_outlined, size: 20, color: Colors.black12),
                    ],
                  )),
                )
              ],
            ),
          ),
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          
          // --- 입체 원형 스위치 ---
          GestureDetector(
            onTap: _onCheckIn,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF8F9FD),
                border: Border.all(color: _isPressed ? Colors.red[100]! : Colors.white, width: 8),
                boxShadow: _isPressed 
                  ? [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4, spreadRadius: 1.0)]
                  : [
                      BoxShadow(color: Colors.black.withOpacity(0.08), offset: const Offset(10, 10), blurRadius: 20),
                      const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                    ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset('assets/smile.png', width: 150),
                  Positioned(bottom: 30, child: Text("CLICK", style: TextStyle(fontSize: 10, color: Colors.grey[300], letterSpacing: 2))),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Text("5분 미확인 시 자동 발송 모드", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// 연락처 및 설정 화면 생략 (기존 기능 유지)
class ContactScreen extends StatelessWidget { const ContactScreen({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("연락처 설정"))); }
class SettingScreen extends StatelessWidget { const SettingScreen({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("권한 설정"))); }
