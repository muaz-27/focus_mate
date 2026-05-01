import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:focus_mate/providers/snapshots_provider.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

class SnapshotsScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String studentName;

  const SnapshotsScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  ConsumerState<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends ConsumerState<SnapshotsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isRequesting = false;
  bool _isChildOnline = true;
  StreamSubscription<DocumentSnapshot>? _userSub;

  @override
  void initState() {
    super.initState();
    // Listen to snapshotRequest and snapshotError fields
    _userSub = _firestore.collection('users').doc(widget.studentId).snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final bool isCapturingRemote = data['snapshotRequest'] == true;
        final String? snapshotError = data['snapshotError'] as String?;

        if (mounted) {
          // Check device online status
          final bool deviceOnline = data['deviceOnline'] == true;
          final Timestamp? lastSeen = data['lastSeen'] as Timestamp?;
          final bool isRecent = lastSeen != null && 
              DateTime.now().difference(lastSeen.toDate()).inMinutes < 3;

          setState(() {
            _isRequesting = isCapturingRemote;
            _isChildOnline = deviceOnline && isRecent;
          });

          // Show error feedback from the child's device
          if (snapshotError != null && snapshotError.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(snapshotError)),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
            // Clear the error after displaying it
            _firestore.collection('users').doc(widget.studentId).update({
              'snapshotError': FieldValue.delete(),
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  Future<void> _requestCapture() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      await _firestore.collection('users').doc(widget.studentId).update({
        'snapshotRequest': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.camera_alt, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Capture requested…'),
              ],
            ),
            backgroundColor: Colors.indigo.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<void> _cancelCapture() async {
    try {
      await _firestore.collection('users').doc(widget.studentId).update({
        'snapshotRequest': false,
      });
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    } catch (e) {
      debugPrint("Cancel failed: $e");
    }
  }

  Future<void> _deleteSnapshot(String docId) async {
    try {
      // Fetch the document first to check for a Storage URL
      final docRef = _firestore
          .collection('users')
          .doc(widget.studentId)
          .collection('snapshots')
          .doc(docId);
      
      final doc = await docRef.get();
      final data = doc.data();
      
      // Delete the Firebase Storage file if it exists
      if (data != null && data['imageUrl'] != null) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(data['imageUrl']);
          await ref.delete();
        } catch (e) {
          debugPrint('Storage delete failed (may already be deleted): $e');
        }
      }
      
      // Delete the Firestore document
      await docRef.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(String docId) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Snapshot', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text('Are you sure you want to delete this snapshot?', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteSnapshot(docId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final cardColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Snapshots', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            Text(widget.studentName, style: TextStyle(fontSize: 13, color: subtextColor)),
          ],
        ),
        actions: [
          // Online/Offline chip
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _isChildOnline
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isChildOnline
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.red.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: _isChildOnline ? Colors.green : Colors.red.shade400,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isChildOnline ? "Online" : "Offline",
                  style: TextStyle(
                    color: _isChildOnline ? Colors.green : Colors.red.shade400,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenBackground(context, AppColors.roleGradients['companion']!),
        child: SafeArea(
          child: Column(
            children: [
              // Capture button area
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _buildCaptureButton(isDark),
              ),
              // Snapshots grid
              Expanded(
                child: _buildBody(isDark, cardColor, subtextColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: _isRequesting
          ? Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    label: const Text('Capturing...', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade400,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.indigo.shade400,
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _cancelCapture,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          : ElevatedButton.icon(
              onPressed: _isChildOnline ? _requestCapture : null,
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: Text(
                _isChildOnline ? 'Capture Screenshot' : 'Device Offline',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
                disabledBackgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                disabledForegroundColor: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
            ),
    );
  }

  Widget _buildBody(bool isDark, Color cardColor, Color? subtextColor) {
    final snapshotsAsync = ref.watch(snapshotsProvider(widget.studentId));

    return snapshotsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text("Error: $e", style: TextStyle(color: isDark ? Colors.white : Colors.black87))),
      data: (docs) {
        // Filter out any debug error documents
        final validDocs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>?;
          if (data == null) return false;
          final hasUrl = data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty;
          final base64 = data['imageBase64'] as String?;
          final hasLegacy = base64 != null && !base64.startsWith('ERROR:') && base64.length > 100;
          return hasUrl || hasLegacy;
        }).toList();

        if (validDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: isDark ? 0.15 : 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_camera_outlined, size: 52, color: Colors.indigo.shade300),
                ),
                const SizedBox(height: 24),
                Text(
                  'No snapshots yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Capture Screenshot" to take\na screenshot of the child\'s device.',
                  style: TextStyle(color: subtextColor, height: 1.5, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: validDocs.length,
          itemBuilder: (context, index) {
            final doc = validDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final imageUrl = data['imageUrl'] as String?;
            final base64Str = data['imageBase64'] as String?;
            final timestamp = data['timestamp'] as Timestamp?;
            final dateStr = timestamp != null
                ? DateFormat('MMM dd, hh:mm a').format(timestamp.toDate())
                : 'Unknown';

            Uint8List? imageBytes;
            if (base64Str != null) {
              try { imageBytes = base64Decode(base64Str); } catch (_) {}
            }

            return GestureDetector(
              onTap: () => _showFullscreen(context, imageBytes, imageUrl, dateStr),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image
                    Expanded(
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildBrokenImage(isDark),
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isDark ? Colors.indigo.shade300 : Colors.indigo,
                                  ),
                                );
                              },
                            )
                          : imageBytes != null
                              ? Image.memory(
                                  imageBytes,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildBrokenImage(isDark),
                                )
                              : _buildBrokenImage(isDark),
                    ),
                    // Footer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: subtextColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              dateStr,
                              style: TextStyle(fontSize: 11, color: subtextColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _confirmDelete(doc.id),
                            child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBrokenImage(bool isDark) => Container(
    color: isDark ? Colors.grey[850] : Colors.grey[100],
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 32, color: Colors.grey[500]),
          const SizedBox(height: 6),
          Text('Unavailable', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
        ],
      ),
    ),
  );

  void _showFullscreen(BuildContext context, Uint8List? bytes, String? imageUrl, String dateStr) {
    if (bytes == null && imageUrl == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageUrl != null 
                    ? Image.network(imageUrl, fit: BoxFit.contain)
                    : Image.memory(bytes!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
