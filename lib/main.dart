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

// 포그라운드 서비스 핸들러
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
          message: "⚠️ 안심 지키미: 설정된 시간($interval) 동안 사용자의 응답이 없습니다. 확인이 필요합니다.",
        );
      }
      // 중복 발송 방지를 위해 현재 시간으로 갱신
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

    // ✅ 빌드 로그 에러 해결: NotificationChannelImportance -> NotificationImportance로 수정
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check',
        channelName: '안심 지키미',
        channelImportance: NotificationImportance.MAX, // 수정됨
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(
          resType: ResourceType.drawable,
          resPrefix: ResourcePrefix.img, // 로그 에러 해결: img 사용
          name: 'btn_star', // Manifest의 @android:drawable/btn_star와 일치
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
      selectedItemColor: Colors.indigo,
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
  String lastCheck = "기록 없음";

  @override
  void initState() { super.initState(); init(); }

  void init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final date = (snap.data()?['lastTimestamp'] as Timestamp?)?.toDate();
        if (date != null) setState(() => lastCheck = DateFormat('MM-dd HH:mm').format(date));
      }
    });
  }

  void checkIn() async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lastTimestamp': DateTime.now(),
    }, SetOptions(merge: true));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("안심 체크 완료")));
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.favorite, size: 100, color: Colors.redAccent),
        const SizedBox(height: 20),
        Text("마지막 체크: $lastCheck", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: checkIn,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
          child: const Text("안심 체크하기", style: TextStyle(fontSize: 18)),
        ),
      ],
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("기록"), centerTitle: true),
    body: const Center(child: Text("자동 발송된 내역이 여기에 표시됩니다.")),
  );
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool on = false;
  String uid = "";

  @override
  void initState() { super.initState(); init(); }

  void init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    uid = info.id;
  }

  Future<void> _setInterval(String value) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'checkInterval': value,
    }, SetOptions(merge: true));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("간격이 $value로 설정됨")));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("실시간 감시 서비스", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Switch(
          value: on,
          onChanged: (v) async {
            setState(() => on = v);
            if (v) {
              await FlutterForegroundTask.startService(
                notificationTitle: "안심 지키미 작동 중",
                notificationText: "상태를 실시간으로 확인하고 있습니다.",
                callback: startCallback,
              );
            } else {
              await FlutterForegroundTask.stopService();
            }
          },
        ),
        const SizedBox(height: 40),
        const Text("비응답 문자 발송 간격 설정"),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            ElevatedButton(onPressed: () => _setInterval("5m"), child: const Text("5분")),
            ElevatedButton(onPressed: () => _setInterval("1h"), child: const Text("1시간")),
            ElevatedButton(onPressed: () => _setInterval("12h"), child: const Text("12시간")),
            ElevatedButton(onPressed: () => _setInterval("24h"), child: const Text("24시간")),
          ],
        ),
      ],
    ),
  );
}
