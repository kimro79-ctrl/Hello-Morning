import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:background_sms/background_sms.dart';
import 'dart:isolate';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  String uid = "";

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    if (uid.isEmpty) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final last = data['lastTimestamp'];
    if (last == null) return;

    final lastTime = (last as Timestamp).toDate();
    final now = DateTime.now();

    // 🔥 시간 설정 읽기
    String interval = data['checkInterval'] ?? "12h";

    int limitMinutes = 720; // 기본 12시간

    if (interval == "5m") limitMinutes = 5;
    if (interval == "1h") limitMinutes = 60;
    if (interval == "12h") limitMinutes = 720;
    if (interval == "24h") limitMinutes = 1440;

    if (now.difference(lastTime).inMinutes >= limitMinutes) {
      List contacts = data['contacts'] ?? [];

      for (var c in contacts) {
        String number = c['number'].toString().replaceAll('-', '');

        await BackgroundSms.sendMessage(
          phoneNumber: number,
          message: "⚠️ 안심 지키미: 설정된 시간 동안 응답이 없습니다.",
        );
      }

      // 🔥 중복 방지
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'lastTimestamp': now,
      });
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

// ================= 앱 시작 =================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const MainNavigation(),
      );
}

// ================= 메인 =================

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _idx = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    HistoryScreen(),
    SettingScreen()
  ];

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await [
      Permission.notification,
      Permission.sms,
      Permission.locationAlways
    ].request();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check',
        channelName: '안심 지키미',
        channelImportance: NotificationChannelImportance.max,
        priority: NotificationPriority.high,
        iconData: const NotificationIconData(
          resType: ResourceType.drawable,
          resPrefix: ResourcePrefix.img,
          name: 'btn_star',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 60000,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _idx, children: _pages),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _idx,
          onTap: (i) => setState(() => _idx = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
          ],
        ),
      );
}

// ================= 홈 =================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String uid = "";

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
  }

  void checkIn() async {
    final now = DateTime.now();

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lastTimestamp': now,
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("체크 완료")));
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: checkIn,
          child: const Text("안심 체크"),
        ),
      );
}

// ================= 기록 =================

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text("기록"));
}

// ================= 설정 =================

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool on = false;
  String uid = "";

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
  }

  Future<void> _setInterval(String value) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'checkInterval': value,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Switch(
            value: on,
            onChanged: (v) async {
              setState(() => on = v);

              if (v) {
                await FlutterForegroundTask.startService(
                  notificationTitle: "안심 지키미",
                  notificationText: "작동 중",
                  callback: startCallback,
                );
              } else {
                await FlutterForegroundTask.stopService();
              }
            },
          ),

          // 🔥 테스트용 시간 선택
          ElevatedButton(onPressed: () => _setInterval("5m"), child: const Text("5분")),
          ElevatedButton(onPressed: () => _setInterval("1h"), child: const Text("1시간")),
          ElevatedButton(onPressed: () => _setInterval("12h"), child: const Text("12시간")),
          ElevatedButton(onPressed: () => _setInterval("24h"), child: const Text("24시간")),
        ],
      );
}
