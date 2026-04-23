import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:async';

void main() => runApp(const HelloMorningApp());

class HelloMorningApp extends StatelessWidget {
  const HelloMorningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hello Morning', // 나중에 "안녕 아침"으로 변경 가능
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _lastCheckIn = "No record yet";
  String _emergencyContact = "Not set";
  String _contactName = "Guardian";
  bool _isWinking = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastCheckIn = prefs.getString('lastCheckIn') ?? "Smile for the first time today!";
      _emergencyContact = prefs.getString('emergencyNumber') ?? "Not set";
      _contactName = prefs.getString('emergencyName') ?? "Guardian";
    });
  }

  // Smile Button Click
  Future<void> _checkIn() async {
    setState(() => _isWinking = true);

    final prefs = await SharedPreferences.getInstance();
    String now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    await prefs.setString('lastCheckIn', now);
    
    Timer(const Duration(milliseconds: 600), () {
      setState(() {
        _isWinking = false;
        _lastCheckIn = now;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Have a wonderful day! Your smile is beautiful.", 
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.yellow[400],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _pickContact() async {
    if (await Permission.contacts.request().isGranted) {
      final Contact? contact = await ContactsService.openDeviceContactPicker();
      if (contact != null && contact.phones!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        String name = contact.displayName ?? "Guardian";
        String number = contact.phones!.first.value ?? "";
        
        await prefs.setString('emergencyName', name);
        await prefs.setString('emergencyNumber', number);
        
        setState(() {
          _contactName = name;
          _emergencyContact = number;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Hello Morning", 
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.orangeAccent,
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Are you doing well today?", 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 10),
              Text("Last Smile: $_lastCheckIn", 
                style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 60),
              
              // Smile Button
              GestureDetector(
                onTap: _checkIn,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: _isWinking ? Colors.orange[400] : Colors.yellow[400],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 25,
                        spreadRadius: 5,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _isWinking ? Icons.face_retouching_natural : Icons.sentiment_very_satisfied_rounded,
                      size: 100,
                      color: Colors.brown[700],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 80),
              
              // Emergency Contact Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.orange[100]!, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Emergency Contact", 
                          style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text(_contactName, 
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(_emergencyContact, 
                          style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.orange, size: 35),
                      onPressed: _pickContact,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
