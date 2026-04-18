import 'package:flutter/material.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/core/widgets/custom_button.dart';
import 'package:focus_mate/core/widgets/custom_text_field.dart';
import '../core/auth_service.dart';
import '../core/usage_service.dart';
import 'forgot_password_screen.dart';

/// Semantic colors associated with each user role.
final Map<UserRole, Color> roleAccent = {
  UserRole.user: Colors.cyanAccent,
  UserRole.companion: Colors.purpleAccent,
  UserRole.parent: Colors.orangeAccent,
};

/// Screen dealing with existing user authentication.
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

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final UsageService _usageService = UsageService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isFormValid = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  void _validateForm() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isValid = email.isNotEmpty && password.length >= 6;
    if (_isFormValid != isValid) {
      setState(() => _isFormValid = isValid);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Validates the form and attempts to sign in the user.
  /// 
  /// Checks for role mismatch to ensure students don't log in as guardians.
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = await _auth.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      if (user.role != widget.role) {
        await _auth.signOut();
        throw Exception("Role mismatch. This account is registered as a ${user.role.name}.");
      }

      if (widget.role == UserRole.user) {
        await _usageService.syncUsageToFirebase(user.id);
      }

      if (!mounted) return;
      widget.onLogin(widget.role, user.toMap());
    } catch (e) {
      _showError(e.toString().replaceAll("Exception:", "").trim());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent[widget.role]!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] 
              : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
            stops: const [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    label: const Text("Back", style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: Colors.grey[900]!.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
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
                          const Text(
                            "Enter your details to continue",
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 26),

                          CustomTextField(
                            controller: _emailController,
                            hint: "Email",
                            icon: Icons.mail,
                            accentColor: accent,
                            validator: (value) =>
                                (value == null || value.isEmpty) ? "Please enter your email" : null,
                          ),
                          const SizedBox(height: 18),

                          CustomTextField(
                            controller: _passwordController,
                            hint: "Password",
                            icon: Icons.lock,
                            accentColor: accent,
                            isPassword: true,
                            validator: (value) =>
                                (value == null || value.isEmpty) ? "Please enter your password" : null,
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ForgotPasswordScreen(role: widget.role),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                "Forgot Password?",
                                style: TextStyle(color: accent, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),

                          CustomButton(
                            onPressed: _isFormValid ? _handleLogin : null,
                            text: "Sign In",
                            isLoading: _isLoading,
                            color: _isFormValid ? accent : Colors.grey,
                          ),

                          const SizedBox(height: 14),

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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

