import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'auth_screen.dart'; // Make sure this path is correct
import 'auth_service.dart'; // Make sure this path is correct

// --- This is the StatefulWidget class ---
class LoginScreen extends StatefulWidget {
  final UserRole role;
  final VoidCallback onBack;
  final Function(UserRole role, dynamic userData) onLogin;
  final VoidCallback onSwitchToSignup;

  const LoginScreen({
    super.key,
    required this.role,
    required this.onBack,
    required this.onLogin,
    required this.onSwitchToSignup,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
// --- End of StatefulWidget class ---


// --- This is the updated State class ---
class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  // --- ADD THIS ---
  final AuthService _auth = AuthService();
  // --- END ADD ---

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _isLoading = false;

  late AnimationController _iconController;
  late Animation<double> _iconAnimation;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _iconAnimation = Tween<double>(begin: 0, end: 1).animate(_iconController);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  // --- ADD THIS HELPER FUNCTION ---
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
  // --- END ADD ---

  // --- THIS IS THE UPDATED LOGIN FUNCTION ---
  void _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      // 1. Get text from controllers
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // 2. Call AuthService to sign in
      final user = await _auth.signIn(email, password);

      if (user == null) {
        // AuthService returns null on failure
        throw FirebaseAuthException(code: 'user-not-found', message: 'Invalid email or password.');
      }

      // 3. Fetch user data from Firestore
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!docSnapshot.exists) {
        // This is an edge case, but good to check
        await _auth.signOut(); // Sign out the auth user
        throw Exception('User data not found. Please sign up again.');
      }

      // 4. CRITICAL: Verify the role
      final userData = docSnapshot.data()!;
      final storedRole = userData['role']; // e.g., 'parent'
      final selectedRole = widget.role.name; // e.g., 'user'

      if (storedRole != selectedRole) {
        // Mismatch! Log them out immediately and show an error.
        await _auth.signOut();
        throw Exception(
            'Role mismatch. You are registered as a $storedRole.');
      }

      // 5. Role matches! Proceed.
      if (!mounted) return;
      widget.onLogin(widget.role, userData);

    } on FirebaseAuthException catch (e) {
      // Handle Firebase errors (e.g., wrong-password)
      _showError(e.message ?? 'Login failed.');
    } catch (e) {
      // Handle other errors (like our custom role mismatch)
      _showError(e.toString());
    } finally {
      // 6. Stop loading
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  // --- END UPDATED FUNCTION ---

  @override
  Widget build(BuildContext context) {
    //
    // NO CHANGES NEEDED to your build() method.
    // Your UI code is already correctly calling _handleLogin.
    //
    final roleConfig = {
      UserRole.user: {
        'title': 'Student Login',
        'colors': [Colors.cyanAccent, Colors.blueAccent],
      },
      UserRole.companion: {
        'title': 'Companion Login',
        'colors': [Colors.purpleAccent, Colors.pinkAccent],
      },
      UserRole.parent: {
        'title': 'Parent Login',
        'colors': [Colors.orangeAccent, Colors.redAccent],
      },
    };

    final config = roleConfig[widget.role]!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              children: [
                // Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Card container
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: (config['colors'] as List)
                          .map((c) => (c as Color).withOpacity(0.15))
                          .toList(),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey[900]?.withOpacity(0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Animated Icon
                      RotationTransition(
                        turns: _iconAnimation,
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white24,
                          child: Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        config['title'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enter your credentials',
                        style: TextStyle(color: Colors.grey.shade300),
                      ),
                      const SizedBox(height: 20),

                      // Email Input
                      TextField(
                        controller: _emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.mail,
                            color: Colors.white70,
                          ),
                          hintText: 'you@example.com',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white24,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password Input
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.lock,
                            color: Colors.white70,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.white70,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                          hintText: '••••••••',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white24,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: (config['colors'] as List)[0],
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Switch to Signup
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Don\'t have an account? ',
                            style: TextStyle(color: Colors.grey),
                          ),
                          TextButton(
                            onPressed: widget.onSwitchToSignup,
                            child: const Text(
                              'Sign up',
                              style: TextStyle(color: Colors.cyanAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}