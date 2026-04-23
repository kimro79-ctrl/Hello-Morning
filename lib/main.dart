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
      title: '하루 안부 지킴이',
      theme: ThemeData(
        primarySwatch: Colors.orange,
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
  List<Map<String, String>> _contacts = []; // 연락처 5개 저장 리스트
  bool _isPressed = false;

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
    String? contactJson = prefs.getString('contacts');
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요!";
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(
            json.decode(contactJson).map((item) => Map<String, String>.from(item)));
      }
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contacts', json.encode(_contacts));
  }

  // 등록된 모든 연락처로 문자 발송 (수동 실행)
  Future<void> _sendEmergencySMS() async {
    if (_contacts.isEmpty) return;

    final String message = "[하루 안부 지킴이] 사용자의 안부 확인이 지연되었습니다. 확인 부탁드립니다.";
    
    // 안드로이드/iOS 통합 방식: 콤마(,)로 번호를 구분하여 여러 명에게 발송 시도
    final List<String> numbers = _contacts.map((c) => c['number']!).toList();
    final String numbersString = numbers.join(Theme.of(context).platform == TargetPlatform.iOS ? ',' : ';');
    
    final Uri smsUri = Uri.parse('sms:$numbersString?body=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("문자 발송 앱을 열 수 없습니다.")),
        );
      }
    }
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isPressed = false);
    });

    setState(() => _lastCheckIn = now);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("안부 확인 완료!"), backgroundColor: Colors.green),
    );
  }

  Future<void> _pickContact() async {
    if (_contacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("연락처는 최대 5개까지 등록 가능합니다.")),
      );
      return;
    }

    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null && contact.phones!.isNotEmpty) {
        setState(() {
          _contacts.add({
            'name': contact.displayName ?? "이름 없음",
            'number': contact.phones!.first.value ?? "",
          });
        });
        await _saveContacts();
      }
    }
  }

  void _removeContact(int index) {
    setState(() {
      _contacts.removeAt(index);
    });
    _saveContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFA726), Color(0xFFFFB74D)],
            ),
          ),
          child: AppBar(
            title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey)),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 40),
            
            // 입체 스위치
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEFF0F3),
                    boxShadow: _isPressed
                        ? [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4)]
                        : [BoxShadow(color: Colors.black.withOpacity(0.15), offset: const Offset(10, 10), blurRadius: 20),
                           const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20)],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipOval(
                        child: Image.asset('assets/smile.png', width: 160, height: 160, fit: BoxFit.cover),
                      ),
                      const Positioned(
                        bottom: 25,
                        child: Text("CLICK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // 보호자 목록 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("보호자 연락처 (최대 5개)", style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(onPressed: _pickContact, icon: const Icon(Icons.add_circle, color: Colors.orange)),
                    ],
                  ),
                  ...List.generate(_contacts.length, (index) => Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.6),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(_contacts[index]['name']!),
                      subtitle: Text(_contacts[index]['number']!),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                        onPressed: () => _removeContact(index),
                      ),
                    ),
                  )),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            if (_contacts.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _sendEmergencySMS,
                icon: const Icon(Icons.send),
                label: const Text("전체 보호자에게 문자 전송"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(250, 50),
                ),
              ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
