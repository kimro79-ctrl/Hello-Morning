import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:direct_sms/direct_sms.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
import 'dart:convert';

// 배경에서 실행될 자동 발송 로직
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckInStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts_list');
    
    // 테스트를 위해 5분(5) 또는 운영용 24시간(1440)으로 설정 가능
    const int limitMinutes = 1440; 

    if (lastCheckInStr != null && contactJson != null) {
      DateTime lastCheck = DateFormat('yyyy-MM-dd HH:mm').parse(lastCheckInStr);
      int difference = DateTime.now().difference(lastCheck).inMinutes;

      // 기준 시간을 초과하면 자동으로 문자 발송
      if (difference >= limitMinutes) {
        List<dynamic> contacts = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        
        for (var c in contacts) {
          try {
            await directSms.sendSms(
              message: "[하루 안부 지킴이] 사용자의 안부 확인이 지연되어 자동 발송된 메시지입니다.",
              phone: c['number'],
            );
          } catch (e) {
            debugPrint("자동 발송 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 배경 작업 초기화
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    "safety_check_task",
    "periodicSafetyCheck",
    frequency: const Duration(minutes: 15), // 안드로이드 최소 주기
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MainScreen(),
  ));
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요";
      String? contactJson = prefs.getString('contacts_list');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _checkIn() async {
    _controller.forward().then((_) => _controller.reverse());
    setState(() => _isPressed = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _isPressed = false);
    });

    setState(() => _lastCheckIn = now);
  }

  Future<void> _pickContact() async {
    if (_contacts.length >= 5) return;
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null && contact.phones!.isNotEmpty) {
        setState(() {
          _contacts.add({
            'name': contact.displayName ?? "보호자",
            'number': contact.phones!.first.value ?? ""
          });
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('contacts_list', json.encode(_contacts));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        // 1. 파스텔톤 오렌지 배경 + 강조된 블랙 텍스트
        title: const Text("하루 안부 지킴이", 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87)),
        backgroundColor: const Color(0xFFFFE0B2), 
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 50),
            const Text("마지막 확인 시간", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 60),
            
            GestureDetector(
              onTap: _checkIn,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFDFDFD),
                    // 2. 누를 때 테두리 붉은색 효과
                    border: Border.all(
                      color: _isPressed ? Colors.redAccent : Colors.white,
                      width: 4,
                    ),
                    boxShadow: _isPressed ? [] : [
                      BoxShadow(color: Colors.black.withOpacity(0.08), offset: const Offset(10, 10), blurRadius: 20),
                      const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipOval(child: Image.asset('assets/smile.png', width: 150, fit: BoxFit.cover, 
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.face, size: 100, color: Colors.orange))),
                      // 2. CLICK 텍스트 작게
                      Positioned(
                        bottom: 30,
                        child: Text("CLICK", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 2)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
            
            // 보호자 목록 리스트
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Container(
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.all(15),
                child: Column(
                  children: [
                    const Text("등록된 보호자", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ..._contacts.map((c) => ListTile(
                      dense: true,
                      title: Text(c['name']!, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(c['number']!),
                      trailing: IconButton(icon: const Icon(Icons.remove_circle, size: 18, color: Colors.black12), 
                        onPressed: () { setState(() => _contacts.remove(c)); }),
                    )),
                    if (_contacts.length < 5)
                      TextButton.icon(onPressed: _pickContact, icon: const Icon(Icons.add, size: 16), label: Text("보호자 추가 (${_contacts.length}/5)")),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            const Text("24시간 미확인 시 자동으로 문자가 발송됩니다.", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
            const SizedBox(height: 20),
            
            // 수동 설정 버튼
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text("시스템 설정 (배터리 최적화 해제 필수)", style: TextStyle(fontSize: 11, color: Colors.blueGrey, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}
