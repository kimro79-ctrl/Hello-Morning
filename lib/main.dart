import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert'; // 연락처 저장을 위한 json 디코더

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
  List<Map<String, String>> _contacts = []; // 연락처 5개를 위한 리스트
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
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요!";
      String? contactJson = prefs.getString('contacts_list');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(
            json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contacts_list', json.encode(_contacts));
  }

  Future<void> _sendEmergencySMS() async {
    if (_contacts.isEmpty) return;
    // 첫 번째 보호자에게 테스트 문자 발송
    final String number = _contacts.first['number']!;
    final String message = "[하루 안부 지킴이] 사용자의 안부 확인이 지연되었습니다.";
    final Uri smsUri = Uri.parse('sms:$number?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
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
      const SnackBar(
        content: Text("안부가 확인되었습니다!", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orangeAccent,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _pickContact() async {
    if (_contacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("연락처는 최대 5개까지 등록 가능합니다."))
      );
      return;
    }

    if (await Permission.contacts.request().isGranted) {
      try {
        final Contact? contact = await ContactsService.openDeviceContactPicker();
        if (contact != null && contact.phones!.isNotEmpty) {
          setState(() {
            _contacts.add({
              'name': contact.displayName ?? "보호자",
              'number': contact.phones!.first.value ?? ""
            });
          });
          await _saveContacts();
        }
      } catch (e) {
        debugPrint("연락처 선택 오류: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFFA726), Color(0xFFFFB74D)],
            ),
            boxShadow: [BoxShadow(color: Colors.black12, offset: Offset(0, 3), blurRadius: 5)],
          ),
          child: AppBar(
            title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
        ),
      ),
      body: SingleChildScrollView( // 연락처가 많아질 경우 대비
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Column(
            children: [
              const Text("마지막 확인 시간", style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 60),
              
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
                      color: const Color(0xFFEFF0F3),
                      boxShadow: _isPressed
                          ? [
                              BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4, spreadRadius: 1),
                              const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4, spreadRadius: 1),
                            ]
                          : [
                              BoxShadow(color: Colors.black.withOpacity(0.15), offset: const Offset(10, 10), blurRadius: 20),
                              const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                            ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
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
                        Positioned(
                          bottom: 25,
                          child: Text(
                            "CLICK",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _isPressed ? Colors.orange : Colors.grey[400],
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 60),
              
              // 보호자 연락처 목록 (최대 5개)
              if (_contacts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      ..._contacts.map((contact) => ListTile(
                        dense: true,
                        title: Text(contact['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(contact['number']!),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
                          onPressed: () async {
                            setState(() => _contacts.remove(contact));
                            await _saveContacts();
                          },
                        ),
                      )),
                      const Divider(),
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
              TextButton.icon(
                onPressed: _pickContact,
                icon: const Icon(Icons.person_add_alt),
                label: Text("보호자 연락처 추가 (${_contacts.length}/5)"),
              ),
              
              // 배터리 최적화 제외 수동 권한 버튼
              TextButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.battery_alert, size: 16),
                label: const Text("문자가 안 오나요? (배터리 제한 해제)", 
                  style: TextStyle(fontSize: 12, color: Colors.grey, decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
