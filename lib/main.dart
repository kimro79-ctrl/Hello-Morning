import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:direct_sms/direct_sms.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DailySafetyApp());
}

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
  String _lastCheckIn = "오늘의 안부를 확인해주세요";
  List<Map<String, String>> _contacts = [];
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
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요";
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

  // 직접 문자 발송 권한 및 기능
  Future<void> _sendTestSMS() async {
    if (_contacts.isEmpty) {
      _showSnackBar("등록된 보호자가 없습니다.");
      return;
    }

    // 문자 및 전화 권한 확인
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.contacts,
    ].request();

    if (statuses[Permission.sms]!.isGranted) {
      final DirectSms directSms = DirectSms();
      final String number = _contacts.first['number']!;
      
      try {
        await directSms.sendSms(
          message: "[하루 안부 지킴이] 테스트 메시지입니다. 사용자의 안부가 확인되었습니다.",
          phone: number,
        );
        _showSnackBar("첫 번째 보호자에게 테스트 문자를 보냈습니다.");
      } catch (e) {
        _showSnackBar("발송 실패: $e");
      }
    } else {
      _showSnackBar("문자 발송 권한이 거부되었습니다.");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _isPressed = false);
    });

    setState(() => _lastCheckIn = now);
  }

  Future<void> _pickContact() async {
    if (_contacts.length >= 5) {
      _showSnackBar("보호자는 최대 5명까지 등록 가능합니다.");
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
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.normal, fontSize: 17, color: Colors.black87)),
        backgroundColor: const Color(0xFFF7B13E),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Column(
            children: [
              const Text("마지막 확인 시간", style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              Text(_lastCheckIn, style: const TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 60),
              
              GestureDetector(
                onTap: _checkIn,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFEFF0F3),
                      boxShadow: _isPressed
                          ? [
                              BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4),
                              const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4),
                            ]
                          : [
                              BoxShadow(color: Colors.black.withOpacity(0.12), offset: const Offset(10, 10), blurRadius: 18),
                              const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 18),
                            ],
                    ),
                    child: Center(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/smile.png',
                          width: 150,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(Icons.face, size: 90, color: Color(0xFFF7B13E)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 60),
              
              // 보호자 리스트 (최대 5개)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    const Text("등록된 보호자", style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 10),
                    ..._contacts.map((contact) => ListTile(
                      dense: true,
                      title: Text(contact['name']!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                      subtitle: Text(contact['number']!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.black26, size: 20),
                        onPressed: () async {
                          setState(() => _contacts.remove(contact));
                          await _saveContacts();
                        },
                      ),
                    )),
                    if (_contacts.length < 5)
                      TextButton.icon(
                        onPressed: _pickContact,
                        icon: const Icon(Icons.person_add_alt, size: 18),
                        label: Text("보호자 추가 (${_contacts.length}/5)", style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // 기능 버튼들
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _sendTestSMS,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.redAccent,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("문자 테스트", style: TextStyle(fontSize: 13)),
                  ),
                  ElevatedButton(
                    onPressed: () => openAppSettings(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("권한 수동설정", style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              
              const SizedBox(height: 30),
              const Text("5분 미확인 시 자동으로 문자가 발송됩니다.", 
                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
