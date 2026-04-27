import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('auto_sms_enabled') ?? false)) return;

    String? last = p.getString('lastCheckIn');
    String? contactsJson = p.getString('contacts_list');
    int selectedHours = p.getInt('selectedHours') ?? 1;

    if (last == null || contactsJson == null || contactsJson == "[]") return;

    DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(last);
    int limitMin = selectedHours == 0 ? 5 : selectedHours * 60;

    if (DateTime.now().difference(lastTime).inMinutes >= limitMin) {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      List contacts = json.decode(contactsJson);
      String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";

      for (var c in contacts) {
        await BackgroundSms.sendMessage(
          phoneNumber: c['number'],
          message: "[안심 지키미] 응답 지연 발생!\n위치 확인: $googleMapsUrl"
        );
      }

      await p.setString('lastCheckIn', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

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
      scaffoldBackgroundColor: const Color(0xFFF5F5DC),
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
  void initState() {
    super.initState();
    _initForegroundTask();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNoticeDialog();
    });
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check_channel',
        channelName: '안심 지키미 서비스',
        channelDescription: '사용자의 안전 상태를 실시간으로 모니터링합니다.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher'
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 180000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void _showNoticeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFFF8A65)),
            SizedBox(width: 10),
            Text("필수 기능 안내", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("보호를 위해 백그라운드 위치(항상 허용)와 SMS 발송 권한이 반드시 필요합니다."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initPermissions();
            },
            child: const Text("확인 및 설정", style: TextStyle(color: Color(0xFF5C6BC0), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _initPermissions() async {
    await [Permission.sms, Permission.contacts, Permission.location, Permission.notification].request();
    if (await Permission.location.isGranted) {
      await Permission.locationAlways.request();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _currentIndex, children: _screens),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: const Color(0xFFFF8A65),
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
      ],
    ),
  );
}

// 🔥 HomeScreen, SettingScreen는 UI 변경 없이 그대로 유지됨 (span만 제거됨)
// 👉 너 코드 그대로 유지 가능
