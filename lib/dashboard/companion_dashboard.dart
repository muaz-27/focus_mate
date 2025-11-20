import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/auth_service.dart';

class CompanionDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function onLogout;

  const CompanionDashboard({
    super.key,
    required this.userData,
    required this.onLogout,
  });

  @override
  State<CompanionDashboard> createState() => _CompanionDashboardState();
}

class _CompanionDashboardState extends State<CompanionDashboard> {
  String? linkCode;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadLinkCode();
  }

  Future<void> _loadLinkCode() async {
    final doc = await _firestore
        .collection('users')
        .doc(widget.userData['id'])
        .get();
    setState(() {
      linkCode = doc.data()?['linkCode'];
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      6,
      (index) => chars[Random().nextInt(chars.length)],
    ).join();
  }

  Future<void> _refreshCode() async {
    final code = _generateCode();
    await _firestore.collection('users').doc(widget.userData['id']).update({
      'linkCode': code,
    });
    setState(() {
      linkCode = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Companion Dashboard"),
        actions: [
          IconButton(
            onPressed: () => widget.onLogout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title: const Text("Link Code"),
                subtitle: Text(linkCode ?? "Press refresh to generate"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshCode,
                    ),
                    if (linkCode != null)
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: linkCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Code copied!")),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Show linked students
            StreamBuilder<DocumentSnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(widget.userData['id'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final data = snapshot.data!.data() as Map<String, dynamic>;
                final linked = data['linkedStudents'] as List<dynamic>? ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Linked Students:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (var studentId in linked)
                      FutureBuilder<DocumentSnapshot>(
                        future: _firestore
                            .collection('users')
                            .doc(studentId)
                            .get(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox();
                          final student =
                              snap.data!.data() as Map<String, dynamic>;
                          return ListTile(
                            title: Text(student['name']),
                            subtitle: Text("Student connected"),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
