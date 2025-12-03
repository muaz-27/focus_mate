import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign Up
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    try {
      // First, we create the user in Firebase Authentication
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (result.user == null) return null;

      // Then, we create a user model with all their details
      final newUser = UserModel(
        id: result.user!.uid,
        name: name,
        email: email,
        role: role,
        createdAt: DateTime.now(),
        linkedUsers: (role == UserRole.companion || role == UserRole.parent) ? [] : null,
      );

      // Finally, we save this extra data to the database
      await _firestore.collection('users').doc(newUser.id).set(newUser.toMap());

      return newUser;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Sign In
  Future<UserModel?> signIn(String email, String password) async {
    try {
      // Attempt to sign in with email and password
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user == null) return null;

      // If successful, fetch their profile data from the database
      final userModel = await getUserData(result.user!.uid);
      
      // If no data exists for this user, we must sign out immediately
      // to prevent AuthGate from picking up a "zombie" session.
      if (userModel == null) {
        await signOut();
      }

      return userModel;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Get User Data
  Future<UserModel?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (!doc.exists) return null;
      
      return UserModel.fromMap(doc.data() as Map<String, dynamic>, uid);
    } catch (e) {
      print("Error fetching user data: $e");
      return null;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Error Handler
  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return Exception("Incorrect email or password.");
      case 'email-already-in-use':
        return Exception("This email is already registered.");
      case 'invalid-email':
        return Exception("The email address is badly formatted.");
      case 'weak-password':
        return Exception("The password is too weak.");
      default:
        return Exception(e.message ?? "Authentication failed.");
    }
  }
}