import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:focus_mate/providers/snapshots_provider.dart';

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
  StreamSubscription<DocumentSnapshot>? _userSub;

  @override
  void initState() {
    super.initState();
    // Listen to snapshotRequest field to know when capture completes
    _userSub = _firestore.collection('users').doc(widget.studentId).snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final bool isCapturingRemote = data['snapshotRequest'] == true;
        if (mounted) {
          setState(() {
            _isRequesting = isCapturingRemote;
          });
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Snapshot'),
        content: const Text('Are you sure you want to delete this snapshot?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
    final bgColor = isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF0F2F8);
    final cardColor = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final subtextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        shadowColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Snapshots', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.studentName, style: TextStyle(fontSize: 13, color: subtextColor)),
          ],
        ),
        actions: [
          if (_isRequesting) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton(
                onPressed: _cancelCapture,
                child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                label: const Text('Capturing...', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ] else ...[
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: _requestCapture,
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Capture', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            )
          ]
        ],
      ),
      body: _buildBody(isDark, cardColor, subtextColor),
    );
  }

  Widget _buildBody(bool isDark, Color cardColor, Color? subtextColor) {
    final snapshotsAsync = ref.watch(snapshotsProvider(widget.studentId));

    return snapshotsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.white))),
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
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.indigo.withValues(alpha: 0.15) : Colors.indigo.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_camera_outlined, size: 56, color: Colors.indigo.shade300),
                ),
                const SizedBox(height: 20),
                Text('No snapshots yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 8),
                Text('Tap "Capture" to take a screenshot\nof the child\'s device.',
                  style: TextStyle(color: subtextColor, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: validDocs.length,
          itemBuilder: (context, index) {
            final doc  = validDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final imageUrl   = data['imageUrl'] as String?;
            final base64Str  = data['imageBase64'] as String?;
            final timestamp  = data['timestamp'] as Timestamp?;
            final dateStr    = timestamp != null
                ? DateFormat('MMM dd, yyyy  •  hh:mm a').format(timestamp.toDate())
                : 'Unknown Date';

            Uint8List? imageBytes;
            if (base64Str != null) {
              try { imageBytes = base64Decode(base64Str); } catch (_) {}
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: () => _showFullscreen(context, imageBytes, imageUrl, dateStr),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: imageUrl != null
                          ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity,
                              errorBuilder: (_, __, ___) => _buildBrokenImage(isDark),
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              })
                          : imageBytes != null
                              ? Image.memory(imageBytes, fit: BoxFit.cover, width: double.infinity,
                                  errorBuilder: (_, __, ___) => _buildBrokenImage(isDark))
                              : _buildBrokenImage(isDark),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 15, color: subtextColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(dateStr, style: TextStyle(fontSize: 13, color: subtextColor)),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 22),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(doc.id),
                        ),
                      ],
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

  Widget _buildBrokenImage(bool isDark) => Container(
    height: 160,
    color: isDark ? Colors.grey[850] : Colors.grey[100],
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 36, color: Colors.grey[500]),
          const SizedBox(height: 8),
          Text('Preview unavailable', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    ),
  );

  void _showFullscreen(BuildContext context, Uint8List? bytes, String? imageUrl, String dateStr) {
    if (bytes == null && imageUrl == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageUrl != null 
                    ? Image.network(imageUrl, fit: BoxFit.contain)
                    : Image.memory(bytes!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
