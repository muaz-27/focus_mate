import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_apps/device_apps.dart';

import '../core/gemini_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'pdf_viewer_screen.dart';
import 'quiz_screen.dart';
import 'quiz_review_screen.dart';
import 'quiz_history_screen.dart';
class StudyWorkspaceScreen extends StatefulWidget {
  final String userId;

  const StudyWorkspaceScreen({super.key, required this.userId});

  @override
  State<StudyWorkspaceScreen> createState() => _StudyWorkspaceScreenState();
}

class _StudyWorkspaceScreenState extends State<StudyWorkspaceScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  List<Application> installedApps = [];
  List<String> lockedPackages = [];
  bool loadingApps = true;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: false,
        onlyAppsWithLaunchIntent: true,
      );
      final doc = await _firestore.collection('users').doc(widget.userId).get();

      if (mounted) {
        setState(() {
          installedApps = apps.where((app) => app.packageName != 'com.example.focus_mate').toList();
          installedApps.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

          if (doc.exists) {
            final data = doc.data()!;
            lockedPackages = List<String>.from(data['lockedApps'] ?? []);
          }
          loadingApps = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loadingApps = false);
      }
    }
  }

  void _toggleLockSelection(String packageName) {
    setState(() {
      if (lockedPackages.contains(packageName)) {
        lockedPackages.remove(packageName);
      } else {
        lockedPackages.add(packageName);
      }
    });
  }

  Future<void> _checkAccessibilityAndRun(Future<void> Function() action) async {
    try {
      final bool isEnabled = await platform.invokeMethod('isAccessibilityEnabled');
      if (!isEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.background,
              title: const Text("Permission Required", style: TextStyle(color: Colors.white)),
              content: const Text("Focus Mate requires the Accessibility Service to block apps. Please enable it in your device Settings under Accessibility.", style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK", style: TextStyle(color: Colors.cyanAccent)),
                )
              ]
            )
          );
        }
        return;
      }
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error checking permissions: $e")));
      }
    }
  }

  void _showAppLockPrompt(String buttonText, Future<void> Function() onStart) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Select Apps to Lock during Study",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Apps Grid
                  Expanded(
                    child: loadingApps
                        ? const Center(child: CircularProgressIndicator())
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: installedApps.length,
                            itemBuilder: (context, index) {
                              final app = installedApps[index];
                              final isSelected = lockedPackages.contains(app.packageName);
                              Uint8List? iconData;
                              if (app is ApplicationWithIcon) {
                                iconData = app.icon;
                              }
                              
                              return GestureDetector(
                                onTap: () {
                                  _toggleLockSelection(app.packageName);
                                  setModalState(() {});
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.redAccent.withOpacity(0.2)
                                        : (isDark ? Colors.white.withOpacity(0.05) : Colors.white70),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? Colors.redAccent : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          color: Colors.black.withOpacity(0.3),
                                        ),
                                        child: iconData != null && iconData.isNotEmpty
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: Image.memory(iconData, fit: BoxFit.cover, gaplessPlayback: true),
                                              )
                                            : const Icon(Icons.apps, color: Colors.white54, size: 24),
                                      ),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 2),
                                        child: Text(
                                          app.appName,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black87,
                                            fontSize: 9,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Start Button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close bottom sheet
                          _checkAccessibilityAndRun(onStart);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          buttonText, 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startStudyModeFlow() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, // Crucial: gets bytes directly for Gemini
      );

      if (result != null && result.files.single.path != null) {
        final bytes = result.files.single.bytes;
        if (bytes == null) {
           throw Exception("Failed to read file bytes. Make sure the file exists.");
        }
        
        final fileName = result.files.single.name;

        if (mounted) {
           showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                 backgroundColor: AppColors.background,
                 content: Row(
                    children: [
                       const CircularProgressIndicator(color: Colors.cyanAccent),
                       const SizedBox(width: 20),
                       Expanded(child: Text("Generating quiz from $fileName...", style: const TextStyle(color: Colors.white))),
                    ],
                 )
              ),
           );
        }

        // 1. Extract text and prompt Gemini locally
        final geminiService = GeminiService();
        final quizQuestions = await geminiService.generateQuizFromPdf(bytes);

        if (mounted) {
           Navigator.pop(context); // Close loading indicator
        }

        if (quizQuestions != null && quizQuestions.isNotEmpty) {
          // 2. Lock apps now that quiz is ready
          if (lockedPackages.isNotEmpty) {
            await platform.invokeMethod('setBlockedApps', {'apps': lockedPackages});
            await _firestore.collection('users').doc(widget.userId).update({
              'lockedApps': lockedPackages,
              'lockEndTime': null, // Clear any previous expiration timer
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Apps locked for Study Mode!")),
              );
            }
          }
          
          // 3. Save JSON to Firestore with active tracker fields
          await _firestore
              .collection('users')
              .doc(widget.userId)
              .collection('saved_quizzes')
              .add({
            'sourceName': fileName,
            'questions': quizQuestions,
            'status': 'active', // Important for filtering
            'lastScore': 0,
            'timestamp': FieldValue.serverTimestamp(),
          });
          
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text("Quiz generated and apps locked! You can start the quiz later from 'Take Saved Quiz'.")),
             );
          }
        } else {
           if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Failed to generate quiz. No questions produced.")),
              );
           }
        }
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context); // Close loading indicator safely
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Future<void> _openCurrentQuiz() async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .where('status', isEqualTo: 'active')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text("No active quiz right now! Start a session to lock apps."))
            );
         }
         return;
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      _startQuiz(doc.id, data);
    } catch (e) {
       // Handle missing compound index by filtering on the client side
       final errorString = e.toString().toLowerCase();
       if (errorString.contains('failed-precondition') || errorString.contains('requires an index')) {
          try {
             final fallbackSnapshot = await _firestore
                 .collection('users')
                 .doc(widget.userId)
                 .collection('saved_quizzes')
                 .orderBy('timestamp', descending: true)
                 .get();
                 
             final activeDocs = fallbackSnapshot.docs.where((doc) {
                final data = doc.data();
                return data['status'] == 'active';
             }).toList();
             
             if (activeDocs.isNotEmpty) {
                final doc = activeDocs.first;
                _startQuiz(doc.id, doc.data());
             } else {
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("No active quiz right now! Start a session to lock apps."))
                   );
                }
             }
             return;
          } catch (fallbackErr) {
             if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text("Error getting current quiz: $fallbackErr"))
                );
             }
             return;
          }
       }
       
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Error getting current quiz: $e"))
          );
       }
    }
  }

  void _startQuiz(String docId, Map<String, dynamic> data) {
      final questions = data['questions'] as List<dynamic>? ?? [];
      if (questions.isEmpty) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Selected quiz format invalid.")));
        }
        return;
      }

      final mappedQuestions = questions.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuizScreen(
              userId: widget.userId,
              quizDocId: docId, 
              questions: mappedQuestions,
            ),
          ),
        );
      }
  }

  Future<void> _deleteQuiz(String docId) async {
    try {
      await _firestore
        .collection('users')
        .doc(widget.userId)
        .collection('saved_quizzes')
        .doc(docId)
        .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Quiz deleted from history.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting quiz: $e")));
      }
    }
  }

  Future<void> _pickPdfFile(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        
        // --- Open Local PDF Viewer immediately ---
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(pdfFile: file),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error picking file: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Study Workspace"),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: AppTheme.headerTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.blueAccent),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Useful tools for studying
            const Text("Tools", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildToolCard(
                    "Read PDF",
                    Icons.picture_as_pdf,
                    Colors.redAccent,
                    () => _pickPdfFile(context), 
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildToolCard(
                    "Start Session",
                    Icons.school,
                    Colors.amberAccent,
                    () => _showAppLockPrompt("Next: Pick Material", _startStudyModeFlow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildActiveSessionIndicator(),
            const SizedBox(height: 16),
            const Text("Quiz Management", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildToolCard(
                    "Current Quiz",
                    Icons.play_circle_fill,
                    Colors.cyanAccent,
                    _openCurrentQuiz,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildToolCard(
                    "Quiz History",
                    Icons.history,
                    Colors.greenAccent,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizHistoryScreen(userId: widget.userId))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardOverlay,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title, 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionIndicator() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const SizedBox.shrink(); // Loading state handled subtly
        }

        List<DocumentSnapshot> docs = [];
        
        if (snapshot.hasData) {
           docs = snapshot.data!.docs.where((doc) {
               final data = doc.data() as Map<String, dynamic>;
               return data['status'] == 'active';
           }).toList();
        } else if (snapshot.hasError && snapshot.error.toString().toLowerCase().contains('failed-precondition')) {
           // If index is missing, we can't reliably build a live stream for active only
           // But since Current Quiz button handles fallback manually, we'll just show
           // a generic header if we can't build the stream. 
           return const Text("Active Sessions", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));
        }

        if (docs.isEmpty) {
           return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 const Text("Status", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 12),
                 Container(
                   padding: const EdgeInsets.all(16),
                   decoration: BoxDecoration(
                     color: Colors.greenAccent.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                   ),
                   child: const Row(
                     children: [
                       Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                       SizedBox(width: 12),
                       Expanded(child: Text("No active study session. Apps are unlocked.", style: TextStyle(color: Colors.greenAccent))),
                     ],
                   ),
                 ),
              ]
           );
        }

        final data = docs.first.data() as Map<String, dynamic>;
        final String sourceName = data['sourceName'] ?? 'Unknown Material';
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Active Session", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                   BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_clock, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("STUDYING", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                            Text(sourceName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("Currently Locked Apps:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  lockedPackages.isEmpty 
                    ? const Text("No specific apps selected.", style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: lockedPackages.map((pkg) {
                          // Try to find icon from installed apps list
                          final matches = installedApps.where((a) => a.packageName == pkg);
                          final app = matches.isNotEmpty ? matches.first : null;
                          
                          Uint8List? iconData;
                          String appNameStr = pkg;
                          if (app != null) {
                             appNameStr = app.appName;
                             if (app is ApplicationWithIcon) {
                                iconData = app.icon;
                             }
                          }
                          
                          return Tooltip(
                            message: appNameStr,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black26,
                              ),
                              child: iconData != null && iconData.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(iconData, fit: BoxFit.cover, gaplessPlayback: true),
                                    )
                                  : const Icon(Icons.apps, color: Colors.white54, size: 20),
                            ),
                          );
                        }).toList(),
                      ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openCurrentQuiz,
                      icon: const Icon(Icons.play_arrow, color: Colors.black),
                      label: const Text("Take Quiz to Unlock", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ],
        );
      }
    );
  }
}
