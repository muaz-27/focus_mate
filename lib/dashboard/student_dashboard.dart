import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class StudentDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int studyTime;
  final int dailyGoal;
  final bool activeSession;
  final bool companionActive;
  final bool appsUnlocked;
  final Function onLogout;
  final Function(String) onStartSession;

  const StudentDashboard({
    super.key,
    required this.userData,
    required this.studyTime,
    required this.dailyGoal,
    required this.activeSession,
    required this.companionActive,
    required this.appsUnlocked,
    required this.onLogout,
    required this.onStartSession,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  bool showModeSelector = false;
  final TextEditingController _companionCodeController =
      TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late bool companionActive;
  @override
  void initState() {
    super.initState();
    companionActive = widget.companionActive; // initialize from widget
  }

  @override
  Widget build(BuildContext context) {
    final progress = (widget.studyTime / widget.dailyGoal).clamp(0.0, 1.0);
    final remaining = widget.dailyGoal - widget.studyTime;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardOverlay,
        title: Text("Hi, ${widget.userData['name']}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => widget.onLogout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Quick Action Tiles
            Row(
              children: [
                Expanded(
                  child: _buildTile(
                    "Study Workspace",
                    widget.activeSession ? "Session Active" : "Start Studying",
                    AppColors.roleGradients['user']!,
                    () => setState(() => showModeSelector = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTile(
                    "Study-Pass",
                    "Unlock Apps",
                    AppColors.roleGradients['user']!,
                    () {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTile(
                    "App Lock",
                    widget.appsUnlocked ? "Unlocked" : "Locked",
                    AppColors.roleGradients['user']!,
                    () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTile(
                    "Analytics",
                    "Track Progress",
                    AppColors.roleGradients['user']!,
                    () {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Daily Focus Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardOverlay,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.track_changes, color: Colors.cyanAccent),
                          SizedBox(width: 8),
                          Text(
                            "Daily Focus",
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      Text(
                        "${widget.studyTime}m / ${widget.dailyGoal}m",
                        style: const TextStyle(color: Colors.cyanAccent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    remaining > 0
                        ? "You're $remaining mins away from hitting today's goal 🎯"
                        : "🎉 Goal achieved! Keep up the momentum!",
                    style: TextStyle(
                      color: remaining > 0
                          ? Colors.grey.shade300
                          : Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Companion Mode Card (Prominent)
            // Inside _StudentDashboardState build()
            // Inside StudentDashboard build method, replace Companion Mode section
            GestureDetector(
              onTap: () {}, // Could later open more companion info if needed
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: widget.companionActive
                      ? LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [Color(0xFF1F2937), Color(0xFF374151)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: widget.companionActive
                      ? [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.5),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.group,
                          color: widget.companionActive
                              ? Colors.white
                              : Colors.grey,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Companion Mode",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (widget.companionActive)
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.7),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.companionActive
                          ? "Connected to ${widget.userData['companionName'] ?? 'Unknown'}"
                          : "No active companion",
                      style: TextStyle(color: Colors.grey.shade200),
                    ),
                    const SizedBox(height: 12),
                    if (!widget.companionActive)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _companionCodeController,
                              decoration: InputDecoration(
                                hintText: "Enter Companion Code",
                                filled: true,
                                fillColor: Colors.white12,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              final code = _companionCodeController.text.trim();
                              if (code.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Please enter a code"),
                                  ),
                                );
                                return;
                              }

                              // Search companion by linkCode
                              final query = await _firestore
                                  .collection('users')
                                  .where('linkCode', isEqualTo: code)
                                  .limit(1)
                                  .get();

                              if (query.docs.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Invalid code")),
                                );
                                return;
                              }

                              final companionDoc = query.docs.first;
                              final companionId = companionDoc.id;
                              final companionData = companionDoc.data();

                              // Update Firestore: link student ↔ companion
                              await _firestore
                                  .collection('users')
                                  .doc(widget.userData['id'])
                                  .update({'linkedCompanion': companionId});

                              await _firestore
                                  .collection('users')
                                  .doc(companionId)
                                  .update({
                                    'linkedStudents': FieldValue.arrayUnion([
                                      widget.userData['id'],
                                    ]),
                                  });

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Linked with ${companionData['name']}",
                                  ),
                                ),
                              );

                              setState(() {
                                companionActive = true;
                                widget.userData['companionName'] =
                                    companionData['name'];
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text("Link"),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Mode Selector Modal
            if (showModeSelector)
              AlertDialog(
                title: const Text("Select Session Mode"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showModeSelector = false;
                        });
                        widget.onStartSession("Focused");
                      },
                      child: const Text("Focused Mode"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showModeSelector = false;
                        });
                        widget.onStartSession("Pomodoro");
                      },
                      child: const Text("Pomodoro Mode"),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => showModeSelector = false),
                    child: const Text("Cancel"),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(
    String title,
    String subtitle,
    List<Color> gradient,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardContainer(gradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
