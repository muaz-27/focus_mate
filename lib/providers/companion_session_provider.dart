import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/user_provider.dart';

/// Streams the active companion session for the current student user.
///
/// Returns the session document data (Map) if an ACTIVE session exists,
/// or null if no session is active. Used by DashboardRouter to redirect
/// students to CompanionControlledPage.
final activeCompanionSessionProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('companion_sessions')
      .where('userId', isEqualTo: userId)
      .where('status', isEqualTo: 'ACTIVE')
      .limit(1)
      .snapshots()
      .map((snapshot) {
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    final data = doc.data();
    data['id'] = doc.id;
    return data;
  });
});
