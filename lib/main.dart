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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFEFF0F3), useMaterial3: true),
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
        selectedItemColor: Colors.orangeAccent,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: '설정'),
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
  int _selectedHour = 24;
  final List<int> _options = [1, 12, 24, 36];
  Timer? _checkTimer;
  String? _lastSentKey;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) => _autoCheck());
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "안부를 확인해 주세요";
      _selectedHour = prefs.getInt('selectedHour') ?? 24;
    });
  }

  Future<void> _autoCheck() async {
    final prefs = await SharedPreferences.getInstance();
    String? last = prefs.getString('lastCheckIn');
    String? contacts = prefs.getString('contacts_list');

    if (last != null && contacts != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
      if (DateTime.now().difference(lastTime).inHours >= _selectedHour) {
        String key = DateFormat('yyyyMMddHHmm').format(DateTime.now());
        if (_lastSentKey != key) {
          try {
            Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            String mapLink = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
            List list = json.decode(contacts);
            for (var c in list) {
              await BackgroundSms.sendMessage(
                phoneNumber: c['number'],
                message: "[하루안부] ${_selectedHour}시간 미응답.\n마지막 확인: $last\n위치: $mapLink",
              );
            }
            _lastSentKey = key;
          } catch (e) {
            // 위치 실패 시에도 문자 발송 시도
            List list = json.decode(contacts);
            for (var c in list) {
              await BackgroundSms.sendMessage(
                phoneNumber: c['number'],
                message: "[하루안부] ${_selectedHour}시간 미응답.\n마지막 확인: $last\n(위치 정보 확인 불가)",
              );
            }
            _lastSentKey = key;
          }
        }
      }
    }
  }

  void _click() async {
    setState(() => _isPressed = true);
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastCheckIn', now);
    _lastSentKey = null;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; _lastCheckIn = now; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("하루 안심 지키미", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFFFCC80), centerTitle: true),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _options.map((h) => ChoiceChip(
              label: Text("${h}시간"),
              selected: _selectedHour == h,
              onSelected: (val) async {
                setState(() => _selectedHour = h);
                (await SharedPreferences.getInstance()).setInt('selectedHour', h);
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 12)),
          Text(_lastCheckIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: _click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: const Color(0xFFEFF0F3),
                border: Border.all(color: _isPressed ? const Color(0xFFFFD1DC) : Colors.white, width: 10),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(5, 5))],
              ),
              child: const Icon(Icons.face, size: 100, color: Colors.orangeAccent),
            ),
          ),
          const Spacer(),
          Text("$_selectedHour시간 동안 확인이 없으면 보호자에게 문자가 발송됩니다", style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          const SizedBox(height: 40),
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
  List<Map<String, String>> _contacts = [];
  @override
  void initState() { super.initState(); _loadContacts(); }
  void _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('contacts_list');
    if (data != null) setState(() => _contacts = List<Map<String, String>>.from(json.decode(data).map((i) => Map<String, String>.from(i))));
  }
  void _addContact() async {
    if (_contacts.length >= 5) return;
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null) {
        String name = contact.displayName ?? "보호자";
        String number = contact.phones?.isNotEmpty == true ? contact.phones!.first.value ?? "" : "";
        setState(() => _contacts.add({'name': name, 'number': number}));
        (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 설정"), backgroundColor: const Color(0xFFFFCC80)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(child: ListView.builder(itemCount: _contacts.length, itemBuilder: (context, i) => Card(child: ListTile(title: Text(_contacts[i]['name']!), subtitle: Text(_contacts[i]['number']!), trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () async {
              setState(() => _contacts.removeAt(i));
              (await SharedPreferences.getInstance()).setString('contacts_list', json.encode(_contacts));
            }))))),
            ElevatedButton(onPressed: _addContact, child: const Text("보호자 추가")),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () async => await [Permission.sms, Permission.location].request(), child: const Text("권한 허용 확인"))),
          ],
        ),
      ),
    );
  }
}
