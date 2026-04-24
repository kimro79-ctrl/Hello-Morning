import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
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
      title: '하루 한번 안심지킴이',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFDFCFB), useMaterial3: true),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const HomeScreen(), const SettingScreen()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFFFF8A65),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '설정'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastCheckIn = "기록 없음";
  int _selectedMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 확인하세요";
      _selectedMinutes = p.getInt('selectedMinutes') ?? 5;
    });
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() => _lastCheckIn = now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("하루 한번 안심지킴이", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFF3E0),
        elevation: 0,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("마지막 체크인 기록", style: TextStyle(color: Colors.grey)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          Center(
            child: GestureDetector(
              onTap: _updateCheckIn,
              child: Container(
                width: 200, height: 200,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)]),
                child: const Icon(Icons.sentiment_very_satisfied, size: 100, color: Color(0xFFFFAB91)),
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Text("미응답 시 보호자에게 비상 문자가 전송됩니다.", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      ),
    );
  }
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  List _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void _loadContacts() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _contacts = json.decode(p.getString('contacts_list') ?? "[]"));
  }

  // 연락처 권한 수동 설정 창
  void _openPermissionSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("연락처 권한 필요"),
        content: const Text("연락처를 추가하려면 [설정 이동]을 눌러 '연락처' 권한을 허용해 주세요."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(onPressed: () { openAppSettings(); Navigator.pop(context); }, child: const Text("설정 이동")),
        ],
      ),
    );
  }

  Future<void> _addContact() async {
    var status = await Permission.contacts.status;
    
    if (status.isGranted) {
      try {
        final Contact? c = await ContactsService.openDeviceContactPicker();
        if (c != null && c.phones!.isNotEmpty) {
          setState(() => _contacts.add({'name': c.displayName ?? "이름없음", 'number': c.phones?.first.value ?? ""}));
          final p = await SharedPreferences.getInstance();
          await p.setString('contacts_list', json.encode(_contacts));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("연락처를 불러오지 못했습니다.")));
      }
    } else {
      // 권한 요청 후 거절되면 설정창 다이얼로그 띄움
      if (await Permission.contacts.request().isGranted) {
        _addContact();
      } else {
        _openPermissionSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 등록"), backgroundColor: const Color(0xFFFFF3E0)),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(_contacts[i]['name']),
              subtitle: Text(_contacts[i]['number']),
              trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              onPressed: _addContact,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8A65), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
              child: const Text("연락처에서 추가"),
            ),
          ),
        ],
      ),
    );
  }
}
