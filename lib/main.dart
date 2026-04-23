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
      title: 'Hello Morning',
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
          content: const Text("Have a wonderful day!", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.yellow[400],
          behavior: SnackBarBehavior.floating,
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
      appBar: AppBar(title: const Text("Hello Morning"), backgroundColor: Colors.orangeAccent),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Last Smile: $_lastCheckIn"),
            const SizedBox(height: 50),
            GestureDetector(
              onTap: _checkIn,
              child: CircleAvatar(
                radius: 80,
                backgroundColor: Colors.yellow[400],
                child: Icon(_isWinking ? Icons.face_retouching_natural : Icons.sentiment_very_satisfied_rounded, size: 80, color: Colors.brown),
              ),
            ),
            const SizedBox(height: 50),
            Text("Emergency: $_contactName ($_emergencyContact)"),
            ElevatedButton(onPressed: _pickContact, child: const Text("Set Contact")),
          ],
        ),
      ),
    );
  }
}
