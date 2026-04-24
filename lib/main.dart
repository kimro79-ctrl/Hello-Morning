import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';
import 'package:direct_sms/direct_sms.dart';
import 'dart:async';
import 'dart:convert';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimeStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts');
    final int waitMinutes = prefs.getInt('waitTime') ?? 1440;

    if (lastTimeStr != null && contactJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      if (DateTime.now().difference(lastTime).inMinutes >= waitMinutes) {
        List<dynamic> decoded = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        for (var item in decoded) {
          try {
            await directSms.sendSms(
              message: "[하루 안부 지킴이] 설정하신 시간 동안 안부 확인이 없어 발송된 메시지입니다.",
              phone: item['number'].toString(),
            );
          } catch (e) {
            debugPrint("SMS 발송 에러: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    "1",
    "safety_check",
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
  runApp(const MaterialApp(
    home: MainScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  List<Map<String, String>> _contacts = []; // 최대 5개 연락처 저장
  int _waitTime = 1440;
  bool _isPressed = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _loadData();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
    
    // 배터리 및 백그라운드 권한 요청 (1초 후 실행하여 팝업 누락 방지)
    Timer(const Duration(seconds: 1), () => _requestPermissions());
  }

  // 핵심: 배터리 최적화 제외 권한 요청 로직
  Future<void> _requestPermissions() async {
    // 1. 배터리 최적화 제외 요청 (팝업이 뜨는 핵심 부분)
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    // 2. SMS 및 연락처 권한
    await [Permission.sms, Permission.contacts].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요!";
      _waitTime = prefs.getInt('waitTime') ?? 1440;
      String? contactJson = prefs.getString('contacts');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _saveCheckIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);
    
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    setState(() {
      _lastCheckIn = now;
      Timer(const Duration(milliseconds: 1000), () => setState(() => _isPressed = false));
    });
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 시간 설정 섹션
                _buildSectionTitle("안부 확인 대기 시간", const Color(0xFF3E2723)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _timeChip(60, "1시간", setModalState),
                    _timeChip(720, "12시간", setModalState),
                    _timeChip(1440, "24시간", setModalState),
                  ],
                ),
                const SizedBox(height: 25),
                // 보호자 연락처 섹션 (최대 5개)
                _buildSectionTitle("수신 보호자 (${_contacts.length}/5)", const Color(0xFF0D47A1)),
                ..._contacts.map((c) => ListTile(
                  dense: true,
                  title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF263238))),
                  subtitle: Text(c['number']!, style: const TextStyle(color: Color(0xFF546E7A), fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Color(0xFFD32F2F)),
                    onPressed: () async {
                      _contacts.remove(c);
                      await _saveContacts();
                      setModalState(() {}); setState(() {});
                    },
                  ),
                )),
                if (_contacts.length < 5)
                  TextButton.icon(
                    onPressed: () async {
                      Contact? contact = await ContactsService.openDeviceContactPicker();
                      if (contact != null && contact.phones!.isNotEmpty) {
                        _contacts.add({'name': contact.displayName ?? "보호자", 'number': contact.phones!.first.value!});
                        await _saveContacts();
                        setModalState(() {}); setState(() {});
                      }
                    },
                    icon: const Icon(Icons.add_circle, color: Color(0xFF1976D2)),
                    label: const Text("보호자 추가 (최대 5명)", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1976D2))),
                  ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text("배터리/백그라운드 수동 설정", style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contacts', json.encode(_contacts));
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17)),
    );
  }

  Widget _timeChip(int mins, String label, StateSetter setModalState) {
    bool isSel = _waitTime == mins;
    return GestureDetector(
      onTap: () async {
        _waitTime = mins;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('waitTime', mins);
        setModalState(() {}); setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF4E342E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4E342E), width: 2),
        ),
        child: Text(label, style: TextStyle(color: isSel ? Colors.white : const Color(0xFF4E342E), fontWeight: FontWeight.w900)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF0F3), // 배경색 복구
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(color: Color(0xFF263238), fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: Column(
        children: [
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Color(0xFF607D8B), fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF263238))),
          const Spacer(),
          // 뉴모피즘 입체 버튼 디자인 적용
          GestureDetector(
            onTap: _saveCheckIn,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 240, height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEFF0F3),
                  boxShadow: _isPressed
                      ? [
                          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 4),
                          const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 4),
                        ]
                      : [
                          BoxShadow(color: Colors.black.withOpacity(0.15), offset: const Offset(10, 10), blurRadius: 20),
                          const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                        ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/smile.png',
                        width: 180, height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.face, size: 120, color: Colors.grey),
                      ),
                    ),
                    Positioned(
                      bottom: 30,
                      child: Text("CLICK", style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2,
                        color: _isPressed ? Colors.orange : Colors.grey[400]
                      )),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Text("${_waitTime ~/ 60}시간 미확인 시 자동 발송", style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50),
            child: OutlinedButton(
              onPressed: _showSettings,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF263238), width: 2.5),
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF263238),
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune, size: 26),
                  SizedBox(width: 12),
                  Text("시스템 설정", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
