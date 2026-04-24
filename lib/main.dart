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
              message: "[하루 안부 지킴이] 설정하신 시간 동안 안부 확인이 없어 자동 발송된 문자입니다.",
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

  Future<void> _requestPermissions() async {
    await [
      Permission.sms,
      Permission.contacts,
      Permission.ignoreBatteryOptimizations,
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFF0F0), Color(0xFFFFE5E5)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      // 텍스트를 더 진하게 (Brown 900)
                      const Text("안부 확인 대기 시간", style: TextStyle(color: Color(0xFF3E2723), fontWeight: FontWeight.bold, fontSize: 16)),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF0F7FF), Color(0xFFE5F1FF)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      // 텍스트를 더 진하게 (BlueGrey 900)
                      const Text("보호자 연락처", style: TextStyle(color: Color(0xFF263238), fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      ..._contacts.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          dense: true,
                          title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF212121), fontSize: 15)),
                          subtitle: Text(c['number']!, style: const TextStyle(color: Color(0xFF424242), fontWeight: FontWeight.w500)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Color(0xFFD32F2F), size: 24),
                            onPressed: () async {
                              _contacts.remove(c);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('contacts', json.encode(_contacts));
                              setModalState(() {});
                              setState(() {});
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
                            setModalState(() {});
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.add_circle, size: 22),
                        label: const Text("연락처 추가", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF263238)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text("문자가 안오나요? (앱 권한 설정 바로가기)", style: TextStyle(color: Color(0xFF616161), fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
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
        setModalState(() {});
        setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? const Color(0xFF3E2723) : const Color(0xFFD7CCC8), width: 2),
        ),
        child: Text(label, style: TextStyle(color: isSel ? const Color(0xFF3E2723) : Colors.grey[700], fontWeight: FontWeight.w900)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(color: Color(0xFF455A64), letterSpacing: 1, fontWeight: FontWeight.w900, fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0, centerTitle: true,
      ),
      body: Column(
        children: [
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Color(0xFF546E7A), fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          // 시간 텍스트를 아주 진하게
          Text(_lastCheckIn, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF212121))),
          const Spacer(),
          GestureDetector(
            onTap: _saveCheckIn,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF8F9FB),
                border: Border.all(
                  // 스위치 테두리를 아주 선명한 오렌지나 진한 그레이로
                  color: _isPressed ? Colors.deepOrange : const Color(0xFFCFD8DC),
                  width: 6, 
                ),
                boxShadow: _isPressed ? [
                  BoxShadow(color: Colors.deepOrange.withOpacity(0.3), blurRadius: 20, spreadRadius: 4)
                ] : [
                  const BoxShadow(color: Colors.white, offset: Offset(-10, -10), blurRadius: 20),
                  BoxShadow(color: Colors.black.withOpacity(0.12), offset: const Offset(10, 10), blurRadius: 20),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/smile.png', width: 130, 
                      errorBuilder: (context, e, s) => Icon(Icons.face_retouching_natural, size: 100, color: Colors.grey[400])),
                    const SizedBox(height: 8),
                    // CLICK 글자 강조
                    Text("CLICK", style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 4,
                      color: _isPressed ? Colors.deepOrange : const Color(0xFF90A4AE)
                    )),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          // 경고 문구 강조
          Text("${_waitTime ~/ 60}시간 미확인 시 자동 발송", style: const TextStyle(color: Color(0xFFC62828), fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: OutlinedButton(
              onPressed: _showSettings,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF455A64), width: 2), // 버튼 테두리 강조
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF455A64),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.tune, size: 20, fontWeight: FontWeight.bold), SizedBox(width: 8), Text("시스템 설정", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))],
              ),
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}
