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

// 포그라운드 작업 핸들러
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase 초기화 실패: $e");
  }
  runApp(const DailySafetyApp());
}

class DailySafetyApp extends StatelessWidget {
  const DailySafetyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFFDFCF0),
          useMaterial3: true,
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
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
  int _idx = 0;
  final List<Widget> _pages = const [
    HomeScreen(),
    HistoryScreen(),
    SettingScreen()
  ];

  @override
  void initState() {
    super.initState();
    _initServiceConfig();
  }

  Future<void> _initServiceConfig() async {
    await [
      Permission.notification,
      Permission.sms,
      Permission.locationAlways
    ].request();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safety_check',
        channelName: '안심 지키미',
        channelDescription: '사용자 보호 서비스 작동 중',

        // ✅ 핵심 수정 부분
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
        interval: 5000,
        isOnceEvent: false,
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
          selectedItemColor: const Color(0xFF1A237E),
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
  String _last = "기록 없음";
  String _loc = "위치 확인 중...";
  bool _down = false;
  String _uid = "";

  @override
  void initState() {
    super.initState();
    _initUserId();
  }

  void _initUserId() async {
    var info = await DeviceInfoPlugin().androidInfo;
    _uid = info.id;
    _listenToFirebase();
  }

  void _listenToFirebase() {
    if (_uid.isEmpty) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        setState(() {
          _last = snap.data()?['lastCheckIn'] ?? "기록 없음";
          _loc = snap.data()?['lastLocation'] ?? "위치 정보 없음";
        });
      }
    });
  }

  void _checkIn() async {
    if (_uid.isEmpty) return;

    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (_) {}

    String currentLoc = pos != null
        ? "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}"
        : "확인 불가";

    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'lastCheckIn': now,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastLocation': currentLoc,
    }, SetOptions(merge: true));

    _sendAutoSms("안심 지키미 알림: 체크인이 완료되었습니다. ($currentLoc)");

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("안심 체크인 성공")));
  }

  void _sendAutoSms(String message) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();

    if (snap.exists) {
      List contacts = snap.data()?['contacts'] ?? [];

      for (var contact in contacts) {
        String number =
            contact['number'].toString().replaceAll('-', '');

        SmsStatus status = await BackgroundSms.sendMessage(
          phoneNumber: number,
          message: message,
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('history')
            .add({
          'receiver': contact['name'] ?? '보호자',
          'number': number,
          'message': message,
          'time': DateFormat('MM-dd HH:mm').format(DateTime.now()),
          'status': status == SmsStatus.sent ? "성공" : "실패",
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 80,
              child: const Center(
                child: Text(
                  "안심 지키미",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E)),
                ),
              ),
            ),
            const SizedBox(height: 50),
            const Text("매일 하루 한번 눌러주세요",
                style: TextStyle(fontSize: 15, color: Colors.blueGrey)),
            const SizedBox(height: 30),
            GestureDetector(
              onTapDown: (_) => setState(() => _down = true),
              onTapUp: (_) {
                setState(() => _down = false);
                _checkIn();
              },
              child: AnimatedScale(
                scale: _down ? 0.9 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: const Icon(Icons.sentiment_very_satisfied,
                    size: 160, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 50),
            Text("마지막 체크인: $_last",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text("현재 위치: $_loc",
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _uid = "";

  @override
  void initState() {
    super.initState();
    _getUid();
  }

  void _getUid() async {
    var info = await DeviceInfoPlugin().androidInfo;
    setState(() => _uid = info.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFDFCF0),
        appBar: AppBar(
            title: const Text("문자 발송 기록"),
            centerTitle: true,
            backgroundColor: Colors.transparent),
        body: _uid.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(_uid)
                    .collection('history')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;

                  if (docs.isEmpty) {
                    return const Center(child: Text("발송 내역이 없습니다."));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    padding: const EdgeInsets.all(10),
                    itemBuilder: (c, i) => Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.send_rounded,
                            color: docs[i]['status'] == "성공"
                                ? Colors.blue
                                : Colors.red),
                        title: Text(
                            "${docs[i]['receiver']} - ${docs[i]['status']}"),
                        subtitle: Text(
                            "${docs[i]['time']}\n${docs[i]['message']}"),
                      ),
                    ),
                  );
                },
              ),
      );
}

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _on = false;
  String _uid = "";

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    var info = await DeviceInfoPlugin().androidInfo;
    _uid = info.id;

    FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        setState(
            () => _on = snap.data()?['autoSmsEnabled'] ?? false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text("실시간 안심 서비스 활성화"),
                      subtitle:
                          const Text("백그라운드에서 상태를 감시합니다."),
                      value: _on,
                      activeColor: Colors.indigo,
                      onChanged: (v) async {
                        if (v) {
                          await FlutterForegroundTask.startService(
                            notificationTitle: '안심 지키미 작동 중',
                            notificationText: '정상 작동 중입니다.',
                            callback: startCallback,
                          );
                        } else {
                          await FlutterForegroundTask.stopService();
                        }

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(_uid)
                            .update({'autoSmsEnabled': v});
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading:
                          const Icon(Icons.settings_applications),
                      title: const Text("앱 권한 및 설정"),
                      onTap: () => openAppSettings(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
