import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import 'package:focus_mate/screens/analytics/analytics_screen.dart';
import 'package:focus_mate/screens/locks/remote_app_lock_screen.dart';
import 'package:focus_mate/screens/analytics/snapshots_screen.dart';
import 'package:focus_mate/screens/shared/pdf_viewer_screen.dart';
import 'package:focus_mate/screens/quiz/quiz_history_screen.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:focus_mate/screens/schedule/parent_schedule_list_screen.dart';

class ParentChildControlPage extends StatefulWidget {
  final String studentId;
  final String studentName;

  const ParentChildControlPage({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<ParentChildControlPage> createState() => _ParentChildControlPageState();
}

class _ParentChildControlPageState extends State<ParentChildControlPage> {
  Future<void> _unlinkChild() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unlink Child?'),
        content: const Text('This will remove your monitoring access. The child can re-link later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final firestore = FirebaseFirestore.instance;
    final parentId = FirebaseAuth.instance.currentUser?.uid;
    if (parentId == null) return;

    final batch = firestore.batch();
    // Remove companion from child
    batch.update(firestore.collection('users').doc(widget.studentId), {
      'linkedCompanion': null,
      'linkedCompanionRole': null,
    });
    // Remove child from parent's list
    batch.update(firestore.collection('users').doc(parentId), {
      'linkedStudents': FieldValue.arrayRemove([widget.studentId]),
      'linkedUsers': FieldValue.arrayRemove([widget.studentId]),
    });
    await batch.commit();

    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickPdf() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(pdfFile: file),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking file: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.studentName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.link_off, color: Colors.redAccent),
            tooltip: 'Unlink Child',
            onPressed: _unlinkChild,
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['parent']!,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(isDark),
                const SizedBox(height: 30),
                Text("CONTROLS", style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 16),
                _buildControlTile(
                  context,
                  title: "Analytics & Usage",
                  subtitle: "View screen time and study stats",
                  icon: Icons.bar_chart,
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnalyticsScreen(
                          userId: widget.studentId,
                          userName: widget.studentName,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildControlTile(
                  context,
                  title: "App Limits & Locks",
                  subtitle: "Block distractions remotely",
                  icon: Icons.phonelink_lock,
                  color: Colors.orangeAccent,
                  onTap: () {
                    final parentId = FirebaseAuth.instance.currentUser?.uid ?? '';
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      useSafeArea: true,
                      builder: (context) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("App Locks", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.lock_clock, color: Colors.orangeAccent)
                              ),
                              title: Text("Instant Lock", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                              subtitle: Text("Lock apps right now or with a timer", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RemoteAppLockScreen(
                                      studentId: widget.studentId,
                                      studentName: widget.studentName,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.schedule, color: Colors.cyanAccent)
                              ),
                              title: Text("Schedule Lock", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                              subtitle: Text("Set up recurring app locks", style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ParentScheduleListScreen(
                                      studentId: widget.studentId,
                                      studentName: widget.studentName,
                                      parentId: parentId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      ), // Close SafeArea
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildControlTile(
                  context,
                  title: "Snapshots",
                  subtitle: "View recently captured screens",
                  icon: Icons.camera_alt,
                  color: Colors.cyanAccent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SnapshotsScreen(
                          studentId: widget.studentId,
                          studentName: widget.studentName,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildControlTile(
                  context,
                  title: "Study Analytics (Quizzes)",
                  subtitle: "View quiz history and performance",
                  icon: Icons.quiz_outlined,
                  color: Colors.purpleAccent,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuizHistoryScreen(
                          userId: widget.studentId,
                          isReadOnly: true,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildControlTile(
                  context,
                  title: "Study Material (PDF)",
                  subtitle: "Review shared documents",
                  icon: Icons.picture_as_pdf,
                  color: Colors.redAccent,
                  onTap: _pickPdf,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDark 
              ? [const Color(0xFF3D1E00), const Color(0xFF5A2A00)] 
              : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
            child: Text(
              widget.studentName.isNotEmpty ? widget.studentName[0].toUpperCase() : "?",
              style: const TextStyle(fontSize: 28, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(
                      "Profile Active",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlTile(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}