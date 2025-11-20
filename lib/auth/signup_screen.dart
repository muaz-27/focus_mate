import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:focus_mate/core/dashboard_router.dart';
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

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _isLoading = false;

  late AnimationController _iconController;

  @override
  void dispose() {
    _nameController.dispose();
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

  void _handleSignup() async {
    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final user = await _auth.signUp(email, password);

      if (user == null) {
        throw FirebaseAuthException(code: 'user-creation-failed');
      }

      final userData = {
        'id': user.uid,
        'name': name,
        'email': email,
        'role': widget.role.name,
        'createdAt': FieldValue.serverTimestamp(),
        if (widget.role == UserRole.companion || widget.role == UserRole.parent)
          'linkedUsers': [],
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userData);

      if (!mounted) return;
      widget.onSignup(widget.role, userData);
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Signup failed.');
    } catch (_) {
      _showError('An unexpected error occurred.');
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
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.white70,
                    ),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: AppColors.white70),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.cardContainer(config),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.white24,
                        child: Icon(
                          Icons.person_add,
                          color: AppColors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text("Create Account", style: AppTheme.headerTitle),
                      const SizedBox(height: 4),
                      Text('Create your account', style: AppTheme.subtitle),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: AppTheme.inputDecoration(
                          hint: 'Full Name',
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _emailController,
                        style: const TextStyle(color: AppColors.white),
                        decoration: AppTheme.inputDecoration(
                          hint: 'you@example.com',
                          icon: Icons.mail,
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        style: const TextStyle(color: AppColors.white),
                        decoration: AppTheme.inputDecoration(
                          hint: '••••••••',
                          icon: Icons.lock,
                          suffix: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppColors.white70,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignup,
                          style: AppTheme.primaryButton(config),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppColors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.white,
                                  ),
                                ),
                        ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
