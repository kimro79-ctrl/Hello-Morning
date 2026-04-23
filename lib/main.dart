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
          directSms.sendSms(
            message: "[안부 지킴이] 설정하신 $waitMinutes분간 확인이 없어 자동 발송되었습니다.",
            phone: item['number'].toString(),
          );
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask("1", "safety_check", frequency: const Duration(minutes: 15));
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
    await [Permission.sms, Permission.contacts, Permission.ignoreBatteryOptimizations].request();
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
                // 1. 시간 설정 섹션 (연한 살구/핑크 파스텔 그라데이션)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFE5D9), Color(0xFFFFCAD4)], // 매우 연한 핑크 톤
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text("안부 확인 대기 시간", style: TextStyle(color: Color(0xFF8D5B5B), fontWeight: FontWeight.bold)),
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

                // 2. 보호자 설정 섹션 (연한 민트/스카이 파스텔 그라데이션)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD8E2DC), Color(0xFFB9D6F2)], // 매우 연한 블루/민트 톤
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text("보호자 연락처", style: TextStyle(color: Color(0xFF4A6572), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ..._contacts.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          dense: true,
                          title: Text(c['name']!, style: const TextStyle(color: Color(0xFF4A6572), fontWeight: FontWeight.bold)),
                          subtitle: Text(c['number']!, style: const TextStyle(color: Color(0xFF78909C))),
                          trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE57373)), onPressed: () async {
                            _contacts.remove(c);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('contacts', json.encode(_contacts));
                            setModalState(() {});
                            setState(() {});
                          }),
                        ),
                      )),
                      const SizedBox(height: 5),
                      ElevatedButton.icon(
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
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("연락처 추가"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.8),
                          foregroundColor: const Color(0xFF4A6572),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(15),
          boxShadow
