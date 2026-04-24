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
        // 스위치 효과를 극대화하기 위해 배경을 연한 회색으로 설정
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
  bool _isPressed = false; // 버튼 눌림 상태 관리

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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
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

  // 안부 확인 버튼 클릭 시 실행
  Future<void> _checkIn() async {
    // 애니메이션 실행 (살짝 작아졌다가 커짐)
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    // 1.5초 후 상태 초기화 (레드 테두리 사라짐)
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
      // --- 1. 그라데이션이 적용된 입체적인 AppBar 배너창 ---
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFFFA726), // 주황색
                Color(0xFFFFB74D), // 약간 밝은 주황색 (입체감용)
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                offset: Offset(0, 3),
                blurRadius: 5,
              )
            ],
          ),
          child: AppBar(
            title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent, // 그라데이션이 보이도록 투명 설정
            elevation: 0,
            centerTitle: true,
          ),
        ),
      ),
      // ------------------------------------------------
      
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
            
            // --- 2. 최적화된 입체형 스위치 버튼 (Click 텍스트 포함) ---
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
                    // 배경색과 같은 색을 사용하되 그림자로 입체감을 줌 (뉴모피즘)
                    color: const Color(0xFFEFF0F3),
                    boxShadow: _isPressed
                        ? [
                            // 눌렸을 때: 안으로 들어간 듯한 그림자
                            BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4, spreadRadius: SpreadRadius 1),
                            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4, spreadRadius: SpreadRadius 1),
                          ]
                        : [
                            // 평상시: 밖으로 튀어나온 듯한 그림자 (깊이감 증가)
                            BoxShadow(color: Colors.black.withOpacity(0.15), offset: const Offset(10, 10), blurRadius: 20),
                            const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                          ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 스마일 이미지
                      Container(
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
                      // 이미지 중앙 하단 CLICK 텍스트 (자연스럽게)
                      Positioned(
                        bottom: 25, // 이미지 아래쪽 위치
                        child: Text(
                          "CLICK",
                          style: TextStyle(
                            fontSize: 11, // 작고 깔끔하게
                            fontWeight: FontWeight.bold,
                            // 배경색과 어우러지도록 연한 회색 톤으로 설정
                            color: _isPressed ? Colors.orange : Colors.grey[400],
                            letterSpacing: 2.0, // 글자 간격을 넓혀 가독성 확보
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // --------------------------------------------------------

            const SizedBox(height: 60),
            
            // 보호자 정보 박스 (image_9.png와 동일하게 깔끔하게 묶음)
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
