import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'models/user_model.dart';
import 'screen_capture_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a new user account with the specified role and links it to Firestore.
  /// 
  /// Returns a [UserModel] if successful, or null if creation failed.
  /// Throws [Exception] if an error occurs.
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (result.user == null) return null;

      final newUser = UserModel(
        id: result.user!.uid,
        name: name,
        email: email,
        role: role,
        createdAt: DateTime.now(),
        linkedUsers: (role == UserRole.companion || role == UserRole.parent) ? [] : null,
      );

      await _firestore.collection('users').doc(newUser.id).set(newUser.toMap());

      await result.user!.sendEmailVerification();

      return newUser;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Authenticates a user with email and password.
  /// 
  /// Fetches the [UserModel] from Firestore upon success.
  /// Signs out immediately if the user data is missing in Firestore to prevent invalid states.
  Future<UserModel?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user == null) return null;

      final userModel = await getUserData(result.user!.uid);
      
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

  /// Retrieves user profile data from Firestore.
  Future<UserModel?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      
      if (!doc.exists) return null;
      
      return UserModel.fromMap(doc.data() as Map<String, dynamic>, uid);
    } catch (e) {
      debugPrint("Error fetching user data: $e");
      return null;
    }
  }

  /// Sends a password reset email to the specified address.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        throw Exception("No user found for that email.");
      } else if (e.code == 'invalid-email') {
        throw Exception("Invalid email address format.");
      } else {
        throw Exception(e.message ?? "Failed to send password reset email.");
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    await ScreenCaptureService.stopService();
    await _auth.signOut();
  }

  /// Maps [FirebaseAuthException] codes to user-friendly error messages.
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