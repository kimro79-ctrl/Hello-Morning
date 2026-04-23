import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart'; // 주소록 라이브러리
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart'; // 백그라운드 매니저
import 'package:direct_sms/direct_sms.dart'; // 자동 문자 발송
import 'dart:async';
import 'dart:convert';

// 백그라운드 작업 고유 이름
const String safetyCheckTask = "safetyCheck_5min";

// --- 백그라운드에서 실행될 작업 로직 (앱이 꺼져도 동작) ---
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimeStr = prefs.getString('lastCheckIn');
    final contactJson = prefs.getString('contacts');

    if (lastTimeStr != null && contactJson != null) {
      DateTime lastTime = DateFormat('yyyy-MM-dd HH:mm').parse(lastTimeStr);
      DateTime now = DateTime.now();
      
      // [테스트] 마지막 체크인 후 5분 이상 지났는지 확인
      if (now.difference(lastTime).inMinutes >= 5) {
        List<dynamic> decoded = json.decode(contactJson);
        final DirectSms directSms = DirectSms();
        
        // 등록된 모든 보호자에게 순차적으로 문자 발송
        for (var item in decoded) {
          try {
            await directSms.sendSms(
              message: "[하루 안부 지킴이] 사용자의 안부 확인이 5분간 지연되었습니다. 확인 바랍니다.",
              phone: item['number'].toString(),
            );
          } catch (e) {
            print("발송 실패: $e");
          }
        }
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 백그라운드 서비스 초기화
  await Workmanager().initialize(callbackDispatcher);
  
  // 2. 주기적 작업 예약 (안드로이드 제약상 최소 15분마다 깨어나 5분 경과를 체크함)
  await Workmanager().registerPeriodicTask(
    "1",
    safetyCheckTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );

  runApp(const MaterialApp(home: MainScreen(), debugShowCheckedModeBanner: false));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _lastCheckIn = "기록 없음";
  List<Map<String, String>> _contacts = []; // 연락처 저장 리스트
  bool _isPressed = false; // 스위치 눌림 상태 감지

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestPermissions();
  }

  // 필수 권한 요청 (SMS 전송, 연락처 읽기, 배터리 최적화 제외)
  Future<void> _requestPermissions() async {
    await [
      Permission.sms,
      Permission.contacts,
      Permission.ignoreBatteryOptimizations // 폰이 잠들어도 체크하기 위해 필수
    ].request();
  }

  // 저장된 데이터 불러오기
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "오늘의 안부를 확인해주세요";
      String? contactJson = prefs.getString('contacts');
      if (contactJson != null) {
        _contacts = List<Map<String, String>>.from(json.decode(contactJson).map((i) => Map<String, String>.from(i)));
      }
    });
  }

  // 안부 확인 버튼 (스위치) 클릭 시 로직
  Future<void> _saveCheckIn() async {
    // 1. 색상 변경 효과 실행
    setState(() => _isPressed = true);

    // 2. 시간 저장
    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    // 3. UI 업데이트 및 0.5초 뒤 색상 복구
    setState(() {
      _lastCheckIn = now;
      Timer(const Duration(milliseconds: 500), () => setState(() => _isPressed = false));
    });
  }

  // 폰의 주소록 앱을 열어 연락처 불러오기
  Future<void> _pickContact() async {
    if (await Permission.contacts.request().isGranted) {
      Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null && contact.phones!.isNotEmpty) {
        String name = contact.displayName ?? "이름 없음";
        String number = contact.phones!.first.value ?? "";
        
        // 중복 추가 방지
        if (!_contacts.any((element) => element['number'] == number)) {
          setState(() {
            _contacts.add({'name': name, 'number': number});
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('contacts', json.encode(_contacts));
        }
      }
    }
  }

  // 보호자 연락처 관리 팝업 (하단 시트)
  void _showContactManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("보호자 연락처 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ..._contacts.map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(c['number']!),
                    trailing: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () async {
                      setState(() => _contacts.remove(c));
                      setModalState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('contacts', json.encode(_contacts));
                    }),
                  ),
                )),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _pickContact();
                      setModalState(() {}); // 팝업 UI 갱신
                    },
                    icon: const Icon(Icons.contact_phone),
                    label: const Text("폰에서 연락처 불러오기"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // image_13.png의 디자인을 기초로 스위치 효과 적용
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("하루 안부 지킴이", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          children: [
            const Spacer(),
            const Text("마지막 확인 시간", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 5),
            Text(_lastCheckIn, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            
            // --- 디자인 수정한 입체형 스위치 버튼 (CLICK 포함) ---
            GestureDetector(
              onTap: _saveCheckIn,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 바깥쪽 부드러운 그림자 (image_13.png의 Neumorphism 스타일)
                  Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 30,
                          spreadRadius: 10,
                        )
                      ],
                    ),
                  ),
                  // 안쪽 스위치 몸체: 누르면 색상이 변함 (_isPressed 상태 이용)
                  Container(
                    width: 170, height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 누를 때 주황색, 뗄 때 흰색
                      color: _isPressed ? Colors.orange[100] : Colors.white,
                      boxShadow: [
                        if (!_isPressed) // 평상시에만 튀어나온 입체감 표현
                          BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 15, offset: const Offset(8, 8)),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 스마일 이미지
                          Image.asset('assets/smile.png', width: 120),
                          const SizedBox(height: 3),
                          // 요청하신 CLICK 텍스트 추가
                          Text(
                            "CLICK",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              // 누를 때 더 진한 색으로 변함
                              color: _isPressed ? Colors.orange : Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ----------------------------------------------------
            
            const Spacer(),
            // 안내 문구 (자동 발송 내용 명시)
            const Text("5분 미확인 시 자동으로 문자가 발송됩니다.", style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 30),
            
            // 보호자 설정 버튼 (디자인 유지)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showContactManager,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text("보호자 연락처 설정"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
