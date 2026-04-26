import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path_provider/path_provider.dart';

import 'package:focus_mate/core/gemini_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/screens/shared/pdf_viewer_screen.dart';
import 'package:focus_mate/screens/quiz/quiz_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/quiz_provider.dart';
import 'package:focus_mate/screens/study/widgets/quizzes_grid.dart';
import '../../core/widgets/app_icon_widget.dart';

class StudyWorkspaceScreen extends ConsumerStatefulWidget {
  final String userId;

  const StudyWorkspaceScreen({super.key, required this.userId});

  @override
  ConsumerState<StudyWorkspaceScreen> createState() =>
      _StudyWorkspaceScreenState();
}

class _StudyWorkspaceScreenState extends ConsumerState<StudyWorkspaceScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  List<Application> installedApps = [];
  List<String> lockedPackages = [];
  bool loadingApps = true;
  bool companionActive = false;
  String? companionId;
  String? userName;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: false, // Instant load
        includeSystemApps: false,
        onlyAppsWithLaunchIntent: true,
      );
      final doc = await _firestore.collection('users').doc(widget.userId).get();

      if (mounted) {
        setState(() {
          installedApps = apps
              .where((app) => app.packageName != 'com.example.focus_mate')
              .toList();
          installedApps.sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );

          if (doc.exists) {
            final data = doc.data()!;
            lockedPackages = List<String>.from(data['lockedApps'] ?? []);
            companionId = data['linkedCompanion'] ?? data['linkedParent'];
            companionActive = companionId != null;
            userName = data['name'];
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
      final bool isEnabled = await platform.invokeMethod(
        'isAccessibilityServiceAlive',
      );
      if (!isEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.background,
              title: const Text(
                "Permission Required",
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                "Focus Mate requires the Accessibility Service to block apps. Please enable it in your device Settings under Accessibility.",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "OK",
                    style: TextStyle(color: Colors.cyanAccent),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error checking permissions: $e")),
        );
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 0.75,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: installedApps.length,
                            itemBuilder: (context, index) {
                              final app = installedApps[index];
                              final isSelected = lockedPackages.contains(
                                app.packageName,
                              );

                              return GestureDetector(
                                onTap: () {
                                  _toggleLockSelection(app.packageName);
                                  setModalState(() {});
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.redAccent.withValues(
                                            alpha: 0.2,
                                          )
                                        : (isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.05,
                                                )
                                              : Colors.white70),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.redAccent
                                          : Colors.transparent,
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                        child: AppIconWidget(
                                          packageName: app.packageName,
                                          appName: app.appName,
                                          size: 36,
                                          fallbackFontSize: 24,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: Text(
                                          app.appName,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          buttonText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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

  void _showDurationPickerPrompt(
    String buttonText,
    Future<void> Function(int) onStart,
  ) {
    int selectedDuration = 60; // Default 60 mins

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.5,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                    "Select Study Duration",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your companion will select apps to lock.",
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Duration Slider
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$selectedDuration mins",
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    value: selectedDuration.toDouble(),
                    min: 15,
                    max: 240,
                    divisions: 15,
                    activeColor: Colors.cyanAccent,
                    inactiveColor: isDark ? Colors.white10 : Colors.black12,
                    onChanged: (val) {
                      setModalState(() => selectedDuration = val.toInt());
                    },
                  ),

                  const Spacer(),

                  // Start Button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close bottom sheet
                          onStart(selectedDuration);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          buttonText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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

  // --- Non-companion flow: pick PDF first, then show app lock sheet ---
  Future<void> _pickMaterialThenLockApps() async {
    // Step 1: Pick the PDF file first so the user isn't confused
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error picking file: $e')));
      }
      return;
    }

    if (result == null || result.files.single.bytes == null) return;

    final bytes = result.files.single.bytes!;
    final fileName = result.files.single.name;

    // Step 2: Now show the app-lock selection sheet
    if (mounted) {
      _showAppLockPrompt('Start Study Mode', () async {
        await _generateAndLockApps(bytes, fileName);
      });
    }
  }

  // Generates quiz from already-picked bytes, then locks selected apps.
  Future<void> _generateAndLockApps(
    List<int> bytes,
    String fileName,
  ) async {
    ValueNotifier<String>? quizStatusNotifier;
    try {
      quizStatusNotifier = ValueNotifier<String>('Extracting PDF...');
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => ValueListenableBuilder<String>(
            valueListenable: quizStatusNotifier!,
            builder: (_, statusText, __) => AlertDialog(
              backgroundColor: AppColors.background,
              content: Row(
                children: [
                  const CircularProgressIndicator(color: Colors.cyanAccent),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fileName,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

      final geminiService = GeminiService();
      quizStatusNotifier.value = 'Generating quiz with AI...';
      final quizQuestions = await geminiService.generateQuizFromPdf(bytes);

      // Safe dispose and close dialog
      quizStatusNotifier.dispose();
      quizStatusNotifier = null;
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (quizQuestions == null || quizQuestions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to generate quiz. No questions were produced.'),
            ),
          );
        }
        return;
      }

      // Clean up old active quizzes
      final activeQ = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .where('status', isEqualTo: 'active')
          .get();
      final batch = _firestore.batch();
      for (var doc in activeQ.docs) {
        batch.update(doc.reference, {'status': 'abandoned'});
      }
      await batch.commit();

      // Lock selected apps (if any were chosen)
      if (lockedPackages.isNotEmpty) {
        await platform.invokeMethod('setBlockedApps', {'apps': lockedPackages});
        await _firestore.collection('users').doc(widget.userId).update({
          'lockedApps': lockedPackages,
          'lockEndTime': null,
        });
      }

      // Save quiz to Firestore — include lockedApps so the session check
      // doesn't need to rely on the in-memory lockedPackages list.
      final quizRef = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .add({
            'sourceName': fileName,
            'questions': quizQuestions,
            'status': 'active',
            'lastScore': 0,
            'lockedApps': lockedPackages,
            'timestamp': FieldValue.serverTimestamp(),
          });

      // Navigate directly to the quiz — don't wait for the Firestore listener
      // to rebuild the UI, which can race and immediately mark the quiz abandoned.
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuizScreen(
              userId: widget.userId,
              quizDocId: quizRef.id,
              questions: quizQuestions,
            ),
          ),
        );
      }
    } catch (e) {
      quizStatusNotifier?.dispose();
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // Companion flow: pick PDF first, then pick duration.
  Future<void> _startStudyModeFlowWithDuration(int? duration) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      final bytes = result.files.single.bytes!;
      final fileName = result.files.single.name;

      // Clean up old active quizzes
      final activeQ = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .where('status', isEqualTo: 'active')
          .get();
      final batch = _firestore.batch();
      for (var doc in activeQ.docs) {
        batch.update(doc.reference, {'status': 'abandoned'});
      }
      await batch.commit();

      // Save PDF locally to defer generation until quiz time
      final tempDir = await getApplicationDocumentsDirectory();
      final sanitizedName =
          fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_\.]'), '_');
      final localFile = File('${tempDir.path}/$sanitizedName');
      await localFile.writeAsBytes(bytes);

      // Create companion session request
      final newSessionRef =
          _firestore.collection('companion_sessions').doc();
      await newSessionRef.set({
        'userId': widget.userId,
        'userName': userName ?? 'Student',
        'companionId': companionId,
        'status': 'REQUESTED',
        'type': 'study_session',
        'duration': duration ?? 60,
        'lockedApps': [],
        'quizDocId': null,
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final quizRef = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .add({
            'sourceName': fileName,
            'questions': [],
            'status': 'active',
            'lastScore': 0,
            'timestamp': FieldValue.serverTimestamp(),
            'companionSessionId': newSessionRef.id,
            'localPdfPath': localFile.path,
          });

      await newSessionRef.update({'quizDocId': quizRef.id});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Study session requested! Waiting for companion approval.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
            const SnackBar(
              content: Text(
                "No active quiz right now! Start a session to lock apps.",
              ),
            ),
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
      if (errorString.contains('failed-precondition') ||
          errorString.contains('requires an index')) {
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
                const SnackBar(
                  content: Text(
                    "No active quiz right now! Start a session to lock apps.",
                  ),
                ),
              );
            }
          }
          return;
        } catch (fallbackErr) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Error getting current quiz: $fallbackErr"),
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error getting current quiz: $e")),
        );
      }
    }
  }

  Future<void> _startQuiz(String docId, Map<String, dynamic> data) async {
    final questions = data['questions'] as List<dynamic>? ?? [];
    if (questions.isEmpty) {
      // Deferred quiz generation
      final localPdfPath = data['localPdfPath'];
      if (localPdfPath != null) {
        final localFile = File(localPdfPath);
        if (await localFile.exists()) {
          final bytes = await localFile.readAsBytes();
          final deferredStatusNotifier =
              ValueNotifier<String>('Extracting PDF...');
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => ValueListenableBuilder<String>(
                valueListenable: deferredStatusNotifier,
                builder: (_, statusText, __) => AlertDialog(
                  backgroundColor: AppColors.background,
                  content: Row(
                    children: [
                      const CircularProgressIndicator(color: Colors.cyanAccent),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          List<Map<String, dynamic>>? generatedQuestions;
          try {
            final geminiService = GeminiService();
            deferredStatusNotifier.value = 'Generating quiz with AI...';
            generatedQuestions = await geminiService.generateQuizFromPdf(
              bytes,
            );
            deferredStatusNotifier.dispose();
          } catch (e) {
            deferredStatusNotifier.dispose();
            if (mounted) {
              Navigator.pop(context); // Close dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Quiz generation error: $e')),
              );
            }
            return;
          }
          if (mounted) Navigator.pop(context); // Close dialog

          if (generatedQuestions != null && generatedQuestions.isNotEmpty) {
            await _firestore
                .collection('users')
                .doc(widget.userId)
                .collection('saved_quizzes')
                .doc(docId)
                .update({'questions': generatedQuestions});

            final mappedQuestions = generatedQuestions
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
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
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Failed to generate quiz from the material."),
                ),
              );
            }
          }
        } else {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Error: Study material not found on device."),
              ),
            );
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Error: No questions and no local PDF!"),
            ),
          );
      }
      return;
    }

    final mappedQuestions = questions
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Quiz deleted from history.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error deleting quiz: $e")));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error picking file: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Study Workspace"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        titleTextStyle: AppTheme.headerTitle(context),
        actions: const [],
      ),
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['user']!,
        ),
        child: SafeArea(
          child: _buildWorkspaceBody(),
        ),
      ),
    );
  }

  Widget _buildNoActiveSessionUI() {
    final statusIsDark = Theme.of(context).brightness == Brightness.dark;
    final statusTextColor = statusIsDark ? Colors.white : Colors.black87;
    final indicator = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Status",
          style: TextStyle(
            color: statusTextColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: statusIsDark ? 0.1 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green.shade600),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "No active study session. Apps are unlocked.",
                  style: TextStyle(color: Colors.green.shade700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return QuizzesGrid(
      hasActiveSession: false,
      isWaitingForCompanion: false,
      canTakeQuiz: false,
      loadingApps: loadingApps,
      companionActive: companionActive,
      userId: widget.userId,
      indicator: indicator,
      onReadPdf: () => _pickPdfFile(context),
      onStartStudySession: () {
        if (companionActive) {
          _showDurationPickerPrompt('Next: Pick Material', (duration) async {
            await _startStudyModeFlowWithDuration(duration);
          });
        } else {
          // Non-companion: pick material first, then select apps to lock
          _pickMaterialThenLockApps();
        }
      },
      onOpenCurrentQuiz: _openCurrentQuiz,
    );
  }

  Widget _buildWorkspaceBody() {
    final quizzesAsync = ref.watch(quizzesProvider(widget.userId));

    return quizzesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildNoActiveSessionUI(),
      data: (docs) {
        List<QueryDocumentSnapshot> activeQuizzes = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == 'active';
        }).toList();

        if (activeQuizzes.isEmpty) {
          return _buildNoActiveSessionUI();
        }

        final doc = activeQuizzes.first;
        final data = doc.data() as Map<String, dynamic>;
        final String sourceName = data['sourceName'] ?? 'Unknown Material';
        final String? companionSessionId = data['companionSessionId'];

        if (companionSessionId != null) {
          return _buildCompanionSessionContent(companionSessionId, sourceName);
        }

        // For self-control sessions, check the saved lockedApps field in
        // Firestore (NOT the in-memory lockedPackages list, which may not
        // be populated yet on first render or after a restart).
        final List<dynamic> savedLockedApps = data['lockedApps'] ?? [];
        if (savedLockedApps.isEmpty && lockedPackages.isEmpty) {
          // No apps were ever locked — treat quiz as completeable immediately
          // (session still active; user can take quiz without unlocking anything)
          return QuizzesGrid(
            hasActiveSession: true,
            isWaitingForCompanion: false,
            canTakeQuiz: true,
            loadingApps: loadingApps,
            companionActive: companionActive,
            userId: widget.userId,
            indicator: _buildSelfControlActiveCard(sourceName),
            onReadPdf: () => _pickPdfFile(context),
            onStartStudySession: () {
              if (companionActive) {
                _showDurationPickerPrompt('Next: Pick Material', (duration) async {
                  await _startStudyModeFlowWithDuration(duration);
                });
              } else {
                _pickMaterialThenLockApps();
              }
            },
            onOpenCurrentQuiz: _openCurrentQuiz,
          );
        }

        if (lockedPackages.isEmpty) {
          // Apps were locked before but have since been cleared — session over
          WidgetsBinding.instance.addPostFrameCallback((_) {
            doc.reference.update({'status': 'abandoned'});
          });
          return _buildNoActiveSessionUI();
        }

        return QuizzesGrid(
          hasActiveSession: true,
          isWaitingForCompanion: false,
          canTakeQuiz: true,
          loadingApps: loadingApps,
          companionActive: companionActive,
          userId: widget.userId,
          indicator: _buildSelfControlActiveCard(sourceName),
          onReadPdf: () => _pickPdfFile(context),
          onStartStudySession: () {
            if (companionActive) {
              _showDurationPickerPrompt('Next: Pick Material', (duration) async {
                await _startStudyModeFlowWithDuration(duration);
              });
            } else {
              _pickMaterialThenLockApps();
            }
          },
          onOpenCurrentQuiz: _openCurrentQuiz,
        );
      },
    );
  }

  Widget _buildCompanionSessionContent(
    String companionSessionId,
    String sourceName,
  ) {
    final sessionAsync = ref.watch(
      companionSessionDocProvider(companionSessionId),
    );

    return sessionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: CircularProgressIndicator()),
      data: (sessionSnapshot) {
        if (!sessionSnapshot.exists) {
          return _buildNoActiveSessionUI();
        }
        final sessionData = sessionSnapshot.data() as Map<String, dynamic>;
        final status = sessionData['status'];

        if (status != 'REQUESTED' && status != 'ACTIVE') {
          // The companion session is ended, rejected, cancelled, etc.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _firestore.collection('users').doc(widget.userId).collection('saved_quizzes')
              .where('companionSessionId', isEqualTo: companionSessionId)
              .where('status', isEqualTo: 'active')
              .get().then((snap) {
                for (var doc in snap.docs) doc.reference.update({'status': 'abandoned'});
              });
          });
          return _buildNoActiveSessionUI();
        }

        bool isWaiting = status == 'REQUESTED';
        bool isActive = status == 'ACTIVE';
        bool canTakeQuiz = false;
        Widget sessionIndicator;

        if (isWaiting) {
          sessionIndicator = _buildWaitingBanner(sourceName);
        } else {
          final startedAt = sessionData['startedAt']?.toDate();
          final duration = sessionData['duration'] ?? 60;
          final earlyApproved = sessionData['earlyAttemptApproved'] == true;

          if (earlyApproved) {
            canTakeQuiz = true;
          } else if (startedAt != null) {
            final endTime = startedAt.add(Duration(minutes: duration));
            if (DateTime.now().isAfter(endTime)) canTakeQuiz = true;
          }
          sessionIndicator = _buildActiveSessionCard(
            sourceName,
            sessionData,
            sessionSnapshot.id,
          );
        }

        return QuizzesGrid(
          hasActiveSession: isActive,
          isWaitingForCompanion: isWaiting,
          canTakeQuiz: canTakeQuiz,
          loadingApps: loadingApps,
          companionActive: companionActive,
          userId: widget.userId,
          indicator: sessionIndicator,
          onReadPdf: () => _pickPdfFile(context),
          onStartStudySession: () {
            if (companionActive) {
              _showDurationPickerPrompt('Next: Pick Material', (duration) async {
                await _startStudyModeFlowWithDuration(duration);
              });
            } else {
              _pickMaterialThenLockApps();
            }
          },
          onOpenCurrentQuiz: _openCurrentQuiz,
        );
      },
    );
  }

  Widget _buildWaitingBanner(String sourceName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Active Session",
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withValues(alpha: isDark ? 0.1 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.orangeAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.hourglass_top,
                color: Colors.orangeAccent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "WAITING FOR APPROVAL",
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      sourceName,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Your companion is reviewing your request.",
                      style: TextStyle(color: subtextColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSessionCard(
    String sourceName,
    Map<String, dynamic> sessionData,
    String sessionId,
  ) {
    final startedAt = sessionData['startedAt']?.toDate();
    final duration = sessionData['duration'] ?? 60;
    final earlyRequested = sessionData['earlyQuizRequest'] == true;
    final earlyApproved = sessionData['earlyAttemptApproved'] == true;

    bool canTakeQuiz = false;
    String timeLeftStr = "Calculating...";

    if (earlyApproved) {
      canTakeQuiz = true;
      timeLeftStr = "Early attempt approved!";
    } else if (startedAt != null) {
      final endTime = startedAt.add(Duration(minutes: duration));
      final now = DateTime.now();
      if (now.isAfter(endTime)) {
        canTakeQuiz = true;
        timeLeftStr = "Study time up!";
      } else {
        final diff = endTime.difference(now);
        timeLeftStr = "Quiz unlocks in ${diff.inMinutes}m";
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionTextColor = isDark ? Colors.white : Colors.black87;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Active Session (Companion)",
          style: TextStyle(
            color: sectionTextColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "STUDYING",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          sourceName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  timeLeftStr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Currently Locked Apps:",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final List<dynamic> sessionLockedApps = sessionData['lockedApps'] ?? [];
                  if (sessionLockedApps.isEmpty) {
                    return const Text(
                      "No specific apps selected.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: sessionLockedApps.map((pkgDynamic) {
                      final pkg = pkgDynamic.toString();
                      final matches = installedApps.where((a) => a.packageName == pkg);
                      final app = matches.isNotEmpty ? matches.first : null;
                      String appNameStr = app != null ? app.appName : pkg;

                      return Tooltip(
                        message: appNameStr,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.black26,
                          ),
                          child: AppIconWidget(
                            packageName: pkg,
                            appName: appNameStr,
                            size: 36,
                            fallbackFontSize: 20,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }
              ),
              const SizedBox(height: 16),

              if (canTakeQuiz)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openCurrentQuiz,
                    icon: const Icon(Icons.play_arrow, color: Colors.black),
                    label: const Text(
                      'Take Quiz to Unlock',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cardOverlay,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: earlyRequested
                        ? null
                        : () async {
                            await _firestore
                                .collection('companion_sessions')
                                .doc(sessionId)
                                .update({
                                  'earlyQuizRequest': true,
                                  'earlyAttemptApproved': false,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Early attempt requested."),
                                ),
                              );
                            }
                          },
                    icon: Icon(
                      earlyRequested
                          ? Icons.hourglass_empty
                          : Icons.fast_forward,
                      color: Colors.white,
                    ),
                    label: Text(
                      earlyRequested
                          ? "Waiting for Approval..."
                          : "Request Early Attempt",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelfControlActiveCard(String sourceName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionTextColor = isDark ? Colors.white : Colors.black87;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Active Session",
          style: TextStyle(
            color: sectionTextColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
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
              BoxShadow(
                color: Colors.cyanAccent.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                        const Text(
                          "STUDYING",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          sourceName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "Currently Locked Apps:",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              lockedPackages.isEmpty
                  ? const Text(
                      "No specific apps selected.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: lockedPackages.map((pkg) {
                        // Try to find icon from installed apps list
                        final matches = installedApps.where(
                          (a) => a.packageName == pkg,
                        );
                        final app = matches.isNotEmpty ? matches.first : null;

                        String appNameStr = pkg;
                        if (app != null) {
                          appNameStr = app.appName;
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
                            child: AppIconWidget(
                              packageName: pkg,
                              appName: appNameStr,
                              size: 36,
                              fallbackFontSize: 20,
                            ),
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
                  label: const Text(
                    "Take Quiz to Unlock",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
