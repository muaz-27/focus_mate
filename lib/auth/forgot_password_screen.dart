import 'package:flutter/material.dart';
import 'package:focus_mate/core/auth_service.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/core/widgets/custom_button.dart';
import 'package:focus_mate/core/widgets/custom_text_field.dart';
// To access roleAccent

class ForgotPasswordScreen extends StatefulWidget {
  final UserRole role;

  const ForgotPasswordScreen({super.key, required this.role});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _auth = AuthService();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSuccess = false;

  @override
  void dispose() {
    _emailController.dispose();
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

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _isSuccess = false;
    });

    try {
      await _auth.sendPasswordResetEmail(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isSuccess = true;
      });
    } catch (e) {
      _showError(e.toString().replaceAll("Exception:", "").trim());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        {
          UserRole.user: Colors.cyanAccent,
          UserRole.companion: Colors.purpleAccent,
          UserRole.parent: Colors.orangeAccent,
        }[widget.role] ??
        Colors.cyanAccent;
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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    label: const Text(
                      "Back",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 10),

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
                    child: _isSuccess
                        ? _buildSuccessView(accent)
                        : _buildFormView(accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(Color accent) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(Icons.lock_reset, color: accent, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            "Reset Password",
            style: TextStyle(
              color: accent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Enter your email to receive a reset link.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 26),
          CustomTextField(
            controller: _emailController,
            hint: "Email address",
            icon: Icons.mail,
            accentColor: accent,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return "Please enter your email";
              }
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(value))
                return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: 26),
          CustomButton(
            onPressed: _isLoading ? null : _handleResetPassword,
            text: "Send Reset Link",
            isLoading: _isLoading,
            color: accent,
            textColor: Colors.black,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(Color accent) {
    return Column(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: Colors.green.withValues(alpha: 0.15),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 36),
        ),
        const SizedBox(height: 16),
        Text(
          "Check your inbox",
          style: TextStyle(
            color: accent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "We've sent a password reset link to:\n${_emailController.text.trim()}",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 32),
        CustomButton(
          onPressed: () => Navigator.pop(context),
          text: "Back to Login",
          color: accent,
          textColor: Colors.black,
        ),
      ],
    );
  }
}
