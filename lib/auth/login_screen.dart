import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:focus_mate/core/dashboard_router.dart';
import '../core/auth_service.dart';

// ----------------- ROLE COLORS (GLOBAL) -----------------
final Map<UserRole, Color> roleAccent = {
  UserRole.user: Colors.cyanAccent,
  UserRole.companion: Colors.purpleAccent,
  UserRole.parent: Colors.orangeAccent,
};

// ----------------- MAIN WIDGET -----------------
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

// ----------------- STATE -----------------
class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _isLoading = false;

  late AnimationController _iconController;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  // ----------------- LOGIN FUNCTION -----------------
  void _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final user = await _auth.signIn(email, password);

      if (user == null) {
        throw FirebaseAuthException(
          code: "invalid-credentials",
          message: "Invalid email or password.",
        );
      }

      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        await _auth.signOut();
        throw Exception("User data not found.");
      }

      final data = doc.data()!;
      final storedRole = data["role"];
      final selectedRole = widget.role.name;

      if (storedRole != selectedRole) {
        await _auth.signOut();
        throw Exception("Role mismatch. You are registered as a $storedRole.");
      }

      if (!mounted) return;
      widget.onLogin(widget.role, data);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ----------------- BUILD UI -----------------
  @override
  Widget build(BuildContext context) {
    final accent = roleAccent[widget.role]!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // BACK BUTTON
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  label: const Text(
                    "Back",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 10),

                // MAIN CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: Colors.grey[900]!.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      // ROTATING ICON
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: accent.withValues(alpha: 0.15),
                        child: Icon(Icons.lock, color: accent, size: 32),
                      ),
                      const SizedBox(height: 16),

                      Text(
                        "Login",
                        style: TextStyle(
                          color: accent,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Enter your details to continue",
                        style: TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 26),

                      // EMAIL FIELD
                      _buildInputField(
                        controller: _emailController,
                        hint: "Email",
                        icon: Icons.mail,
                        accent: accent,
                      ),
                      const SizedBox(height: 18),

                      // PASSWORD FIELD
                      _buildInputField(
                        controller: _passwordController,
                        hint: "Password",
                        icon: Icons.lock,
                        accent: accent,
                        obscure: !_showPassword,
                        suffix: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white54,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),

                      const SizedBox(height: 26),

                      // LOGIN BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  "Sign In",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // SWITCH TO SIGNUP
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account?",
                            style: TextStyle(color: Colors.white60),
                          ),
                          TextButton(
                            onPressed: widget.onSwitchToSignup,
                            child: Text(
                              "Sign Up",
                              style: TextStyle(color: accent),
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

  // ----------------- REUSABLE INPUT FIELD -----------------
  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color accent,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: accent),
        suffixIcon: suffix,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white12,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: accent.withValues(alpha: 0.5),
            width: 1.4,
          ),
        ),
      ),
    );
  }
}
