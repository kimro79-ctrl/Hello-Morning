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
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFDFCFB),
        useMaterial3: true,
      ),
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
        unselectedItemColor: const Color(0xFF90A4AE),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: '설정'),
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
  bool _isPressed = false;
  int _selectedMinutes = 5; 

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedMinutes = p.getInt('selectedMinutes') ?? 5;
    });
  }

  void _updateCheckIn() async {
    setState(() => _isPressed = true);
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);
    setState(() {
      _lastCheckIn = now;
      Future.delayed(const Duration(milliseconds: 300), () => _isPressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("하루 한번 안심지킴이", style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFFFFF3E0),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("마지막 체크인 시간", style: TextStyle(color: Color(0xFF90A4AE))),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF455A64))),
          const SizedBox(height: 50),
          Center(
            child: GestureDetector(
              onTap: _updateCheckIn,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 230, height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white,
                  border: Border.all(color: _isPressed ? const Color(0xFFFFCCBC) : Colors.white, width: 10),
                  boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 20)],
                ),
                child: ClipOval(
                  child: Image.asset('assets/smile.png', fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.face_rounded, size: 100, color: Color(0xFFFFAB91))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 50),
          const Text("미응답 시 등록된 보호자에게 위치가 발송됩니다.", style: TextStyle(color: Color(0xFFE57373), fontSize: 12)),
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
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _contacts = json.decode(p.getString('contacts_list') ?? "[]"));
  }

  // 연락처 권한 설정창 유도
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("연락처 권한 필요"),
        content: const Text("연락처를 추가하려면 시스템 설정에서 권한을 직접 허용해 주세요."),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("연락처를 가져오지 못했습니다.")));
      }
    } else {
      if (await Permission.contacts.request().isGranted) {
        _addContact();
      } else {
        _showPermissionDialog();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 등록", style: TextStyle(color: Color(0xFF455A64))), backgroundColor: const Color(0xFFFFF3E0), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (c, i) => ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFCCBC), child: Icon(Icons.person, color: Colors.white)),
              title: Text(_contacts[i]['name'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_contacts[i]['number'] ?? ""),
              trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Color(0xFFE57373)), onPressed: () {
                setState(() => _contacts.removeAt(i));
                SharedPreferences.getInstance().then((p) => p.setString('contacts_list', json.encode(_contacts)));
              }),
            ),
          )),
          Padding(
            padding: const EdgeInsets.all(25.0),
            child: ElevatedButton.icon(
              onPressed: _addContact,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8A65), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 55)),
              icon: const Icon(Icons.contact_phone_rounded), label: const Text("연락처에서 추가"),
            ),
          ),
        ],
      ),
    );
  }
}
