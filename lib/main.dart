import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:background_sms/background_sms.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DailySafetyHome(),
  ));
}

class DailySafetyHome extends StatefulWidget {
  const DailySafetyHome({super.key});
  @override
  State<DailySafetyHome> createState() => _DailySafetyHomeState();
}

class _DailySafetyHomeState extends State<DailySafetyHome> {
  String _lastCheck = "기록 없음";
  bool _isPressed = false;
  int _threshold = 24;
  final List<int> _options = [1, 12, 24, 36];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkSms());
  }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _lastCheck = p.getString('lastCheck') ?? "버튼을 눌러주세요";
      _threshold = p.getInt('threshold') ?? 24;
    });
  }

  Future<void> _checkSms() async {
    final p = await SharedPreferences.getInstance();
    String? last = p.getString('lastCheck');
    String? contacts = p.getString('contacts');
    if (last != null && contacts != null) {
      DateTime lastDate = DateFormat('yyyy-MM-dd HH:mm').parse(last);
      if (DateTime.now().difference(lastDate).inHours >= _threshold) {
        Position pos = await Geolocator.getCurrentPosition();
        String link = "https://www.google.com/maps?q=${pos.latitude},${pos.longitude}";
        List list = json.decode(contacts);
        for (var c in list) {
          await BackgroundSms.sendMessage(
            phoneNumber: c['num'], 
            message: "[하루안부] ${_threshold}시간 미확인.\n위치: $link"
          );
        }
      }
    }
  }

  void _onTap() async {
    setState(() => _isPressed = true);
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setString('lastCheck', now);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() { _isPressed = false; _lastCheck = now; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF0F3),
      appBar: AppBar(title: const Text("하루 안심 지키미"), backgroundColor: const Color(0xFFFFCC80)),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _options.map((h) => ChoiceChip(
              label: Text("${h}시간"),
              selected: _threshold == h,
              onSelected: (s) async {
                setState(() => _threshold = h);
                (await SharedPreferences.getInstance()).setInt('threshold', h);
              },
            )).toList(),
          ),
          const Spacer(),
          Text("마지막 확인: $_lastCheck", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: _onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: const Color(0xFFEFF0F3),
                border: Border.all(color: _isPressed ? const Color(0xFFFFD1DC) : Colors.white, width: 10),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: const Icon(Icons.face, size: 100, color: Colors.orangeAccent),
            ),
          ),
          const Spacer(),
          Text(
            "$_threshold시간 동안 확인이 없으면 보호자에게 문자가 발송됩니다",
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
