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
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFFDFCFB),
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFFF8A65),
        ),
        home: const MainNavigation(),
      );
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
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: const Color(0xFFFF8A65),
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
          ],
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  String _lastCheckIn = "기록 없음";
  String _currentLocationText = "위치 확인 중";
  int _selectedHours = 1;
  Timer? _timer;

  bool _autoSmsEnabled = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween(begin: 1.0, end: 0.92).animate(_controller);

    _loadData();
    _loadAutoSetting();
    _updateLocationDisplay();

    _timer = Timer.periodic(
        const Duration(minutes: 5), (t) => _checkAndSendSms());
  }

  void _loadAutoSetting() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _autoSmsEnabled = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  Future<void> _updateLocationDisplay() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);

      setState(() {
        _currentLocationText =
            "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
      });
    } catch (e) {
      setState(() => _currentLocationText = "위치 확인 불가");
    }
  }

  Future<void> _checkAndSendSms() async {
    final p = await SharedPreferences.getInstance();

    bool autoEnabled = p.getBool('auto_sms_enabled') ?? false;
    if (!autoEnabled) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    if (last == null || contactsJson == null) return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int targetMin = _selectedHours == 0 ? 5 : _selectedHours * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= targetMin) {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);

      String mapLink =
          "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";

      String message =
          "[안심지키미] 응답 없음!\n마지막 확인: $last\n위치: $mapLink";

      List contacts = json.decode(contactsJson);

      for (var c in contacts) {
        if (c['number'] != null) {
          String number =
              c['number'].replaceAll(RegExp(r'[^0-9]'), '');

          try {
            await BackgroundSms.sendMessage(
              phoneNumber: number,
              message: message,
            );
          } catch (e) {
            debugPrint("SMS 실패: $e");
          }
        }
      }

      _updateCheckIn();
    }
  }

  void _updateCheckIn() async {
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheckIn', now);

    setState(() => _lastCheckIn = now);
    _updateLocationDisplay();
  }

  void _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = p.getString('lastCheckIn') ?? "오늘 안부를 전하세요";
      _selectedHours = p.getInt('selectedHours') ?? 1;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("안심 지키미")),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Text(_currentLocationText),
          const SizedBox(height: 20),

          Wrap(
            spacing: 8,
            children: [0, 1, 12, 24].map((h) => ChoiceChip(
              label: Text(h == 0 ? "5분" : "$h시간"),
              selected: _selectedHours == h,
              onSelected: (v) async {
                setState(() => _selectedHours = h);
                (await SharedPreferences.getInstance())
                    .setInt('selectedHours', h);
              },
            )).toList(),
          ),

          const Spacer(),
          Text(_lastCheckIn),
          const SizedBox(height: 30),

          GestureDetector(
            onTap: _updateCheckIn,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: const CircleAvatar(
                radius: 80,
                child: Icon(Icons.favorite, size: 50),
              ),
            ),
          ),

          const Spacer(),
          const Text("미응답 시 보호자에게 자동 문자 전송됨"),
          const SizedBox(height: 20),
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
  bool _autoSmsEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _contacts = json.decode(p.getString('contacts_list') ?? "[]");
      _autoSmsEnabled = p.getBool('auto_sms_enabled') ?? false;
    });
  }

  Future<bool> _confirm() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("자동 전송 동의"),
            content: const Text("미응답 시 자동으로 문자가 전송됩니다."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("동의")),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("설정")),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text("자동 문자 전송"),
            value: _autoSmsEnabled,
            onChanged: (v) async {
              if (v) {
                bool ok = await _confirm();
                if (!ok) return;
              }
              final p = await SharedPreferences.getInstance();
              await p.setBool('auto_sms_enabled', v);
              setState(() => _autoSmsEnabled = v);
            },
          ),

          Expanded(
            child: ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (c, i) => ListTile(
                title: Text(_contacts[i]['name']),
                subtitle: Text(_contacts[i]['number']),
              ),
            ),
          ),

          ElevatedButton(
            onPressed: () async {
              if (await Permission.contacts.request().isGranted) {
                final c = await ContactsService.openDeviceContactPicker();
                if (c != null && c.phones!.isNotEmpty) {
                  setState(() => _contacts.add({
                        'name': c.displayName,
                        'number': c.phones?.first.value
                      }));
                  (await SharedPreferences.getInstance())
                      .setString('contacts_list', json.encode(_contacts));
                }
              }
            },
            child: const Text("보호자 추가"),
          ),
        ],
      ),
    );
  }
}
