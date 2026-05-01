import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/core/auth_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/core/widgets/custom_button.dart';
import 'package:focus_mate/core/widgets/custom_text_field.dart';

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

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _auth = AuthService();

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
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'channel-error':
        return 'Please fill in both email and password.';
      default:
        return 'Login failed. Please check your credentials.';
    }
  }

  void _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final userModel = await _auth.signIn(email, password);

      if (userModel == null) {
        throw Exception('Login failed. Please check your credentials.');
      }

      // Verify the role
      if (userModel.role.name != widget.role.name) {
        await _auth.signOut();
        throw Exception('Role mismatch. You are registered as a ${userModel.role.name}.');
      }

      if (!mounted) return;
      widget.onLogin(widget.role, userModel.toMap());

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
        'title': 'Student Login',
        'colors': AppColors.roleGradients['user']!,
      },
      UserRole.companion: {
        'title': 'Companion Login',
        'colors': AppColors.roleGradients['companion']!,
      },
      UserRole.parent: {
        'title': 'Parent Login',
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
              constraints: BoxConstraints(maxWidth: 420.w),
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
                              Icons.lock,
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
                          'Enter your credentials',
                          style: AppTheme.subtitle(context),
                        ),
                        SizedBox(height: 20.h),
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
                          onPressed: _handleLogin,
                          text: 'Sign In',
                          isLoading: _isLoading,
                          color: (config['colors'] as List)[0],
                        ),
                        SizedBox(height: 14.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Don\'t have an account? ',
                              style: TextStyle(color: isDark ? Colors.grey : Colors.black54),
                            ),
                            TextButton(
                              onPressed: widget.onSwitchToSignup,
                              child: Text(
                                'Sign up',
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
