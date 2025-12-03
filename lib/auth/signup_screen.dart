import 'package:flutter/material.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/core/widgets/custom_button.dart';
import 'package:focus_mate/core/widgets/custom_text_field.dart';
import '../core/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SignupScreen extends StatefulWidget {
  final UserRole role;
  final VoidCallback onBack;
  final Function(UserRole role, dynamic userData) onSignup;
  final VoidCallback onSwitchToLogin;

  const SignupScreen({
    super.key,
    required this.role,
    required this.onBack,
    required this.onSignup,
    required this.onSwitchToLogin,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final AuthService _auth = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isFormValid = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_validateForm);
    _emailController.addListener(_validateForm);
    _passwordController.addListener(_validateForm);
  }

  void _validateForm() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final isValid = name.isNotEmpty && email.isNotEmpty && password.length >= 8;
    if (_isFormValid != isValid) {
      setState(() => _isFormValid = isValid);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = await _auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        role: widget.role,
      );

      if (user == null) {
        throw Exception("Signup failed. Please try again.");
      }

      if (!mounted) return;
      widget.onSignup(widget.role, user.toMap());
    } catch (e) {
      _showError(e.toString().replaceAll("Exception:", "").trim());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = {
      UserRole.user: AppColors.roleGradients['user'],
      UserRole.companion: AppColors.roleGradients['companion'],
      UserRole.parent: AppColors.roleGradients['parent'],
    }[widget.role]!;

    // We pick the first color from the gradient to use for our text fields
    final primaryColor = (config as List<Color>).first;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, color: AppColors.white70),
                    label: const Text('Back', style: TextStyle(color: AppColors.white70)),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.cardContainer(config),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.white24,
                          child: Icon(Icons.person_add, color: AppColors.white, size: 32),
                        ),
                        const SizedBox(height: 12),
                        const Text("Create Account", style: AppTheme.headerTitle),
                        const SizedBox(height: 4),
                        Text('Create your account', style: AppTheme.subtitle),
                        const SizedBox(height: 20),

                        CustomTextField(
                          controller: _nameController,
                          hint: "Full Name",
                          icon: Icons.person,
                          accentColor: primaryColor,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Name is required';
                            if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value)) return 'Name must contain only letters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        CustomTextField(
                          controller: _emailController,
                          hint: "you@example.com",
                          icon: Icons.mail,
                          accentColor: primaryColor,
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Email is required';
                            final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                            if (!emailRegex.hasMatch(value)) return 'Enter a valid email address';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        CustomTextField(
                          controller: _passwordController,
                          hint: "Password",
                          icon: Icons.lock,
                          accentColor: primaryColor,
                          isPassword: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Password is required';
                            if (value.length < 8) return 'Password must be at least 8 characters';
                            if (!value.contains(RegExp(r'[A-Za-z]'))) return 'Must contain at least one letter';
                            if (!value.contains(RegExp(r'[0-9]'))) return 'Must contain at least one number';
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        CustomButton(
                          onPressed: _isFormValid ? _handleSignup : null,
                          text: "Sign Up",
                          isLoading: _isLoading,
                          color: _isFormValid ? primaryColor : Colors.grey,
                          textColor: Colors.white,
                        ),

                        const SizedBox(height: 14),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account?',
                              style: TextStyle(color: Colors.grey),
                            ),
                            TextButton(
                              onPressed: widget.onSwitchToLogin,
                              child: const Text(
                                'Sign in',
                                style: TextStyle(color: Colors.cyanAccent),
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
    );
  }
}

