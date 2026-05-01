import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams UI snapshots for a given student, ordered newest first.
///
/// Returns raw Firestore document snapshots since the screen needs
/// access to both imageUrl and legacy imageBase64 fields.
final snapshotsProvider = StreamProvider.family<List<QueryDocumentSnapshot>, String>((ref, studentId) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(studentId)
      .collection('snapshots')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs);
});
