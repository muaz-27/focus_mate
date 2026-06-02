import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/core/auth_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/core/widgets/custom_button.dart';
import 'package:focus_mate/core/widgets/custom_text_field.dart';

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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _getFriendlyErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'The email address is badly formatted.';
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'weak-password':
        return 'The password is too weak. Please use a stronger one.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Signup failed. Please try again.';
    }
  }

  void _handleSignup() async {
    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final userModel = await _auth.signUp(
        email: email,
        password: password,
        name: name,
        role: widget.role,
      );

      if (userModel == null) {
        throw Exception('Signup failed. Please try again.');
      }

      if (!mounted) return;
      widget.onSignup(widget.role, userModel.toMap());
    } on FirebaseAuthException catch (e) {
      _showError(_getFriendlyErrorMessage(e.code));
    } catch (e) {
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) {
        msg = msg.substring(11);
      }
      _showError(msg);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleConfig = {
      UserRole.user: {
        'title': 'Student Signup',
        'colors': AppColors.roleGradients['user']!,
      },
      UserRole.companion: {
        'title': 'Companion Signup',
        'colors': AppColors.roleGradients['companion']!,
      },
      UserRole.parent: {
        'title': 'Parent Signup',
        'colors': AppColors.roleGradients['parent']!,
      },
    };

    final config = roleConfig[widget.role]!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent, // Let parent background show through
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(18.w),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onBack,
                      icon: Icon(Icons.arrow_back, color: isDark ? Colors.white70 : Colors.black87),
                      label: Text(
                        'Back',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Container(
                    padding: EdgeInsets.all(20.w),
                    decoration: AppTheme.cardContainer(context, config['colors'] as List<Color>),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        RotationTransition(
                          turns: _iconAnimation,
                          child: CircleAvatar(
                            radius: 32.r,
                            backgroundColor: isDark ? Colors.white24 : Colors.black12,
                            child: Icon(
                              Icons.person_add,
                              color: isDark ? Colors.white : Colors.black87,
                              size: 32.sp,
                            ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          config['title'] as String,
                          style: AppTheme.headerTitle(context).copyWith(
                            fontSize: 22.sp,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Create your account',
                          style: AppTheme.subtitle(context),
                        ),
                        SizedBox(height: 20.h),
                        CustomTextField(
                          controller: _nameController,
                          hint: 'Full Name',
                          icon: Icons.person,
                          accentColor: (config['colors'] as List)[0],
                        ),
                        SizedBox(height: 16.h),
                        CustomTextField(
                          controller: _emailController,
                          hint: 'you@example.com',
                          icon: Icons.mail,
                          accentColor: (config['colors'] as List)[0],
                        ),
                        SizedBox(height: 16.h),
                        CustomTextField(
                          controller: _passwordController,
                          hint: '••••••••',
                          icon: Icons.lock,
                          isPassword: true,
                          accentColor: (config['colors'] as List)[0],
                        ),
                        SizedBox(height: 20.h),
                        CustomButton(
                          onPressed: _handleSignup,
                          text: 'Sign Up',
                          isLoading: _isLoading,
                          color: (config['colors'] as List)[0],
                        ),
                        SizedBox(height: 14.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'Already have an account? ',
                                style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onSwitchToLogin,
                              child: Text(
                                'Sign in',
                                style: TextStyle(
                                  color: (config['colors'] as List)[0],
                                  fontWeight: FontWeight.bold,
                                ),
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
      ),
    );
  }
}
