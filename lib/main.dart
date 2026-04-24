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
              message: "[하루 안부 지킴이] 안부 확인이 없어 발송된 메시지입니다.",
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
    "1", "safety_check", 
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
  String _lastCheckIn = "안부를 확인해주세요!";
  List<Map<String, String>> _contacts = [];
  int _waitTime = 1440;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
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
    setState(() => _isPressed = true);
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    setState(() {
      _lastCheckIn = now;
      Timer(const Duration(milliseconds: 500), () => setState(() => _isPressed = false));
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
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 25, right: 25, top: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("보호자 연락처 설정", style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.black87)),
                const SizedBox(height: 20),
                
                ..._contacts.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text("${c['name']} (${c['number']})", style: const TextStyle(fontSize: 14, color: Colors.black45))),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.black26, size: 20),
                        onPressed: () async {
                          _contacts.remove(c);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('contacts', json.encode(_contacts));
                          setModalState(() {}); setState(() {});
                        },
                      ),
                    ],
                  ),
                )),

                if (_contacts.length < 5)
                  InkWell(
                    onTap: () async {
                      if (await Permission.contacts.request().isGranted) {
                        Contact? contact = await ContactsService.openDeviceContactPicker();
                        if (contact != null && contact.phones!.isNotEmpty) {
                          _contacts.add({'name': contact.displayName ?? "보호자", 'number': contact.phones!.first.value!});
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('contacts', json.encode(_contacts));
                          setModalState(() {}); setState(() {});
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add, color: Colors.blueAccent, size: 18),
                          SizedBox(width: 6),
                          Text("연락처 추가하기", style: TextStyle(color: Colors.blueAccent, fontSize: 15, fontWeight: FontWeight.normal)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 5),
                const Divider(thickness: 0.5),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text("배터리 최적화 제외 (수동 설정)", style: TextStyle(color: Colors.grey, fontSize: 12, decoration: TextDecoration.underline)),
                ),
                const SizedBox(height: 15),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.normal, fontSize: 17)),
        backgroundColor: const Color(0xFFF7B13E),
        elevation: 0, centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 50),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 6),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.black54)),
          const Spacer(),
          GestureDetector(
            onTap: _saveCheckIn,
            child: Container(
              width: 210, height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFFF7B13E).withOpacity(0.7), width: 5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Center(
                child: ClipOval(
                  child: Image.asset(
                    'assets/smile.png',
                    width: 150, height: 150,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.face, size: 90, color: Color(0xFFF7B13E)),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const Text("5분 미확인 시 자동으로 문자가 발송됩니다.", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.normal)),
          const SizedBox(height: 25),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 70),
            child: ElevatedButton(
              onPressed: _showSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black54,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text("보호자 및 시스템 설정", style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}
