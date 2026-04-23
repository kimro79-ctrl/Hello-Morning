import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    if (lastTimeStr != null && contactJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      // 5분 미확인 시 자동 발송
      if (DateTime.now().difference(lastTime).inMinutes >= 5) {
        List<dynamic> decoded = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        for (var item in decoded) {
          directSms.sendSms(
            message: "[안부 지킴이] 5분간 확인이 없어 자동 발송되었습니다.",
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
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요";
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

  // 연락처 관리 팝업 (하단 시트)
  void _showContactManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("보호자 연락처 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ..._contacts.map((c) => ListTile(
                  title: Text(c['name']!),
                  subtitle: Text(c['number']!),
                  trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), 
                    onPressed: () async {
                      _contacts.remove(c);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('contacts', json.encode(_contacts));
                      setModalState(() {});
                      setState(() {});
                    }),
                )),
                TextButton.icon(
                  onPressed: () => _addContactDialog(setModalState),
                  icon: const Icon(Icons.add),
                  label: const Text("연락처 추가하기"),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  void _addContactDialog(StateSetter setModalState) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("새 연락처"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: "이름")),
          TextField(controller: phoneController, decoration: const InputDecoration(labelText: "번호"), keyboardType: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(onPressed: () async {
            if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
              _contacts.add({'name': nameController.text, 'number': phoneController.text});
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('contacts', json.encode(_contacts));
              setModalState(() {});
              setState(() {});
              Navigator.pop(context);
            }
          }, child: const Text("저장")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("하루 안부 지킴이"), backgroundColor: Colors.orangeAccent, centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey)),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            
            // 메인 버튼: 누르면 색상이 변하며 피드백 제공
            GestureDetector(
              onTap: _saveCheckIn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isPressed ? Colors.orange[100] : Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 5)],
                  border: Border.all(color: _isPressed ? Colors.orange : Colors.yellow[600]!, width: 5),
                ),
                child: Center(
                  child: ClipOval(
                    child: Image.asset('assets/smile.png', width: 140, 
                      errorBuilder: (context, e, s) => Icon(Icons.sentiment_very_satisfied, size: 120, color: Colors.orange[300])),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 50),
            const Text("5분 미확인 시 자동으로 문자가 발송됩니다.", style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            const SizedBox(height: 30),
            
            ElevatedButton.icon(
              onPressed: _showContactManager,
              icon: const Icon(Icons.settings),
              label: const Text("보호자 연락처 설정"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}
