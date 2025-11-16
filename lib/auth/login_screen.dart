import 'package:flutter/material.dart';
import 'auth_screen.dart';

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

  void _handleLogin() async {
    setState(() => _isLoading = true);

    await Future.delayed(const Duration(seconds: 2));

    final userData = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'email': _emailController.text,
      'name': _emailController.text.split('@')[0],
      'role': widget.role.toString(),
      'createdAt': DateTime.now().toIso8601String(),
      if (widget.role == UserRole.companion || widget.role == UserRole.parent)
        'linkedUsers': [],
    };

    setState(() => _isLoading = false);
    widget.onLogin(widget.role, userData);
  }

  @override
  Widget build(BuildContext context) {
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
