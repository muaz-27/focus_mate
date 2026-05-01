import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams all saved quizzes for a given user, ordered by timestamp descending.
///
/// Returns raw Firestore document snapshots since quiz data is polymorphic
/// (active vs completed quizzes with different field sets).
final quizzesProvider = StreamProvider.family<List<QueryDocumentSnapshot>, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('saved_quizzes')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs);
});

/// Streams a single companion session document by ID.
///
/// Used by the study workspace to monitor the session status
/// (REQUESTED → ACTIVE → ENDED) and determine quiz eligibility.
final companionSessionDocProvider = StreamProvider.family<DocumentSnapshot, String>((ref, sessionId) {
  return FirebaseFirestore.instance
      .collection('companion_sessions')
      .doc(sessionId)
      .snapshots();
});
