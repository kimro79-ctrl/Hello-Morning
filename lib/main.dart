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
      // 현재 시간과 마지막 체크인 시간의 차이 계산
      if (DateTime.now().difference(lastTime).inMinutes >= waitMinutes) {
        List<dynamic> decoded = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        for (var item in decoded) {
          try {
            await directSms.sendSms(
              message: "[하루 안부 지킴이] 설정하신 시간 동안 안부 확인이 없어 자동 발송되었습니다.",
              phone: item['number'].toString(),
            );
          } catch (e) {
            debugPrint("백그라운드 SMS 발송 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  
  // 백그라운드 작업 등록 (15분마다 실행)
  await Workmanager().registerPeriodicTask(
    "1", 
    "safety_check", 
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(
      networkType: NetworkType.not_required, // 네트워크 상관없이 실행
    ),
  );
  
  runApp(const MaterialApp(home: MainScreen(), debugShowCheckedModeBanner: false));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _lastCheckIn = "기록 없음";
  List<Map<String, String>> _contacts = [];
  int _waitTime = 1440;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissions();
  }

  // 백그라운드 발송을 위한 핵심 권한 요청
  Future<void> _requestPermissions() async {
    await [
      Permission.sms,
      Permission.contacts,
      Permission.ignoreBatteryOptimizations, // 핵심: 배터리 최적화 제외
    ].request();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해주세요";
      _waitTime = prefs.getInt('waitTime') ?? 1440;
      String? contactJson = prefs.getString('contacts');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  Future<void> _saveCheckIn() async {
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    setState(() {
      _lastCheckIn = now;
      Timer(const Duration(milliseconds: 400), () => setState(() => _isPressed = false));
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
                // 1. 시간 설정 (배경 대비 강화)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade700, width: 2),
                  ),
                  child: Column(
                    children: [
                      const Text("안부 확인 대기 시간", style: TextStyle(color: Color(0xFF4E342E), fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _timeChip(60, "1시간", setModalState),
                          _timeChip(720, "12시간", setModalState),
                          _timeChip(1440, "24시간", setModalState),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                // 2. 보호자 설정 (선명도 강화)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade700, width: 2),
                  ),
                  child: Column(
                    children: [
                      const Text("보호자 연락처", style: TextStyle(color: Color(0xFF0D47A1), fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 10),
                      ..._contacts.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
                        child: ListTile(
                          dense: true,
                          title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16)),
                          subtitle: Text(c['number']!, style: const TextStyle(color: Color(0xFF424242), fontWeight: FontWeight.bold)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Color(0xFFD32F2F), size: 28),
                            onPressed: () async {
                              _contacts.remove(c);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('contacts', json.encode(_contacts));
                              setModalState(() {}); setState(() {});
                            },
                          ),
                        ),
                      )),
                      TextButton.icon(
                        onPressed: () async {
                          Contact? contact = await ContactsService.openDeviceContactPicker();
                          if (contact != null && contact.phones!.isNotEmpty) {
                            _contacts.add({'name': contact.displayName ?? "무명", 'number': contact.phones!.first.value!});
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('contacts', json.encode(_contacts));
                            setModalState(() {}); setState(() {});
                          }
                        },
                        icon: const Icon(Icons.add_circle, size: 26, color: Color(0xFF0D47A1)),
                        label: const Text("연락처 추가", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0D47A1))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text("문자가 안오나요? (권한/배터리 설정)", style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w900, decoration: TextDecoration.underline)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
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
          border: Border.all(color: const Color(0xFF4E342E), width: 2.5),
        ),
        child: Text(label, style: TextStyle(color: isSel ? Colors.white : const Color(0xFF4E342E), fontWeight: FontWeight.w900)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 22)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: Column(
        children: [
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Color(0xFF424242), fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -1)),
          const Spacer(),
          GestureDetector(
            onTap: _saveCheckIn,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 240, height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: _isPressed ? Colors.deepOrange : Colors.black,
                  width: 10, // 가독성을 위해 테두리 더 두껍게
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 25, offset: const Offset(5, 10)),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.face_retouching_natural, size: 110, color: Colors.black),
                    const SizedBox(height: 10),
                    Text("안전 확인", style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2,
                      color: _isPressed ? Colors.deepOrange : Colors.black
                    )),
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
                side: const BorderSide(color: Colors.black, width: 3),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune, size: 26, color: Colors.black),
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
