import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:background_sms/background_sms.dart';
import 'dart:async';
import 'dart:io';
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
    try { await Firebase.initializeApp(); } catch (_) {}
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

    String interval = data['checkInterval'] ?? "12h";
    int limitMinutes = 720; 

    if (interval == "5m") limitMinutes = 5;
    else if (interval == "1h") limitMinutes = 60;
    else if (interval == "12h") limitMinutes = 720;
    else if (interval == "24h") limitMinutes = 1440;

    if (now.difference(lastTime).inMinutes >= limitMinutes) {
      List contacts = data['contacts'] ?? [];
      for (var c in contacts) {
        String number = c['number'].toString().replaceAll('-', '');
        await BackgroundSms.sendMessage(
          phoneNumber: number,
          message: "⚠️ 안심 지키미 알림: 설정된 시간($interval) 동안 응답이 없습니다. 확인 바랍니다.",
        );
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'lastTimestamp': now});
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

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
        theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFDFCF0), useMaterial3: true),
        home: const MainNavigation(),
      );
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _idx = 0;
  final List<Widget> _pages = const [HomeScreen(), HistoryScreen(), SettingScreen()];

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await [Permission.notification, Permission.sms, Permission.locationAlways].request();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check',
        channelName: '안심 지키미',
        channelImportance: NotificationChannelImportance.MAX, 
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(
          resType: ResourceType.drawable,
          resPrefix: ResourcePrefix.img,
          name: 'btn_star', 
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: false),
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String uid = "";
  void init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
  }
  @override
  void initState() { super.initState(); init(); }

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () async {
            if (uid.isEmpty) return;
            await FirebaseFirestore.instance.collection('users').doc(uid).set({
              'lastTimestamp': DateTime.now(),
            }, SetOptions(merge: true));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("체크 완료")));
          },
          child: const Text("안심 체크"),
        ),
      );
}

class HistoryScreen extends StatelessWidget {
  // ✅ 오타 수정: super.head -> super.key
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("기록 화면"));
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool on = false;
  String uid = "";

  void init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
  }

  @override
  void initState() { super.initState(); init(); }

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
          const Text("자동 감시 모드"),
        ],
      );
}
