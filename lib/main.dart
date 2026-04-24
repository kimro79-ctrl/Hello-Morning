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
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
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
  int _idx = 0;
  final List<Widget> _screens = [const HomeScreen(), const SettingScreen()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        selectedItemColor: Colors.orangeAccent,
        onTap: (i) => setState(() => _idx = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
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
  String _last = "기록 없음";
  bool _isPressed = false;
  int _min = 1440; 
  final List<Map<String, dynamic>> _opts = [
    {'label': '5분', 'v': 5},
    {'label': '1시간', 'v': 60},
    {'label': '12시간', 'v': 720},
    {'label': '24시간', 'v': 1440},
  ];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _last = p.getString('last') ?? "안부를 확인해 주세요";
      _min = p.getInt('min') ?? 1440;
    });
  }

  Future<void> _check() async {
    final p = await SharedPreferences.getInstance();
    String? l = p.getString('last');
    String? c = p.getString('con');
    if (l == null || c == null) return;
    
    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(l);
    if (DateTime.now().difference(lastTime).inMinutes >= _min) {
      try {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        String link = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
        List contacts = json.decode(c);
        for (var item in contacts) {
          await BackgroundSms.sendMessage(
            phoneNumber: item['num'], 
            message: "[하루안부] $_min분 동안 응답이 없습니다.\n마지막 확인: $l\n위치: $link"
          );
        }
        _updateSilent();
      } catch (e) {
        // 위치 실패 시 문자만 발송
      }
    }
  }

  void _updateSilent() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('last', now);
    if (mounted) setState(() { _last = now; });
  }

  void _onTap() async {
    setState(() => _isPressed = true);
    _updateSilent();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("하루 안심 지키미"), backgroundColor: const Color(0xFFFFCC80), centerTitle: true),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _opts.map((o) => ChoiceChip(
              label: Text(o['label']),
              selected: _min == o['v'],
              onSelected: (s) async {
                setState(() => _min = o['v']);
                (await SharedPreferences.getInstance()).setInt('min', o['v']);
              },
            )).toList(),
          ),
          const Spacer(),
          const Text("마지막 확인", style: TextStyle(color: Colors.grey)),
          Text(_last, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: _onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: _isPressed ? Colors.orangeAccent : Colors.white, width: 10),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15)],
              ),
              // 사용자님의 이미지를 다시 넣었습니다. (경로가 다르면 'assets/images/logo.png' 부분을 수정하세요)
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png', 
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.face, size: 100, color: Colors.orangeAccent),
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            "${_min >= 60 ? '${_min ~/ 60}시간' : '$_min분'} 동안 확인이 없으면 문자가 발송됩니다.",
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
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
  List _cons = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _cons = json.decode(p.getString('con') ?? "[]"));
  }
  void _add() async {
    if (await Permission.contacts.request().isGranted) {
      final c = await ContactsService.openDeviceContactPicker();
      if (c != null) {
        setState(() => _cons.add({'name': c.displayName, 'num': c.phones?.first.value}));
        (await SharedPreferences.getInstance()).setString('con', json.encode(_cons));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호자 설정"), backgroundColor: const Color(0xFFFFCC80)),
      body: Column(
        children: [
          Expanded(child: ListView.builder(itemCount: _cons.length, itemBuilder: (c, i) => ListTile(
            title: Text(_cons[i]['name'] ?? ""),
            subtitle: Text(_cons[i]['num'] ?? ""),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
              setState(() => _cons.removeAt(i));
              (await SharedPreferences.getInstance()).setString('con', json.encode(_cons));
            }),
          ))),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                ElevatedButton(onPressed: _add, child: const Text("보호자 추가")),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async => await [Permission.sms, Permission.location, Permission.locationAlways].request(), 
                  child: const Text("모든 권한 다시 허용하기")
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
