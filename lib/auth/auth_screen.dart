import 'package:flutter/material.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/auth/login_screen.dart';
import 'package:focus_mate/auth/signup_screen.dart';

class AuthScreen extends StatefulWidget {
  final Function(UserRole role, dynamic userData) onAuthComplete;

  const AuthScreen({super.key, required this.onAuthComplete});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  UserRole? selectedRole;
  String authMode = 'select';

  List<Map<String, dynamic>> roles = [
    {
      'type': UserRole.user,
      'title': 'Student',
      'description': 'Take control of your focus and study habits',
      'color': [Colors.cyan, Colors.blue],
      'bg': [const Color(0xFF082D30), const Color(0xFF0A1F3A)],
      'icon': Icons.person,
      'features': [
        'Smart app locking',
        'Study-Pass system',
        'Personal analytics',
        'Study workspace',
      ],
    },
    {
      'type': UserRole.companion,
      'title': 'Companion',
      'description': 'Support and monitor study progress',
      'color': [Colors.purple, Colors.pink],
      'bg': [const Color(0xFF1A0A3A), const Color(0xFF3A0A30)],
      'icon': Icons.group,
      'features': [
        'Remote monitoring',
        'App control access',
        'Progress tracking',
        'Real-time updates',
      ],
    },
    {
      'type': UserRole.parent,
      'title': 'Parent',
      'description': 'Guide and protect digital wellbeing',
      'color': [Colors.orange, Colors.red],
      'bg': [const Color(0xFF3D1E00), const Color(0xFF3A0505)],
      'icon': Icons.shield,
      'features': [
        'Full parental controls',
        'Usage restrictions',
        'Safety monitoring',
        'Complete oversight',
      ],
    },
  ];

  void handleRoleSelect(UserRole role) {
    setState(() {
      selectedRole = role;
      authMode = 'login';
    });
  }

  void backToSelect() {
    setState(() {
      selectedRole = null;
      authMode = 'select';
    });
  }

  @override
  Widget build(BuildContext context) {
    // LOGIN VIEW
    if (authMode == 'login' && selectedRole != null) {
      return LoginScreen(
        role: selectedRole!,
        onBack: backToSelect,
        onLogin: widget.onAuthComplete,
        onSwitchToSignup: () {
          setState(() => authMode = 'signup');
        },
      );
    }

    // SIGNUP VIEW
    if (authMode == 'signup' && selectedRole != null) {
      return SignupScreen(
        role: selectedRole!,
        onBack: backToSelect,
        onSignup: widget.onAuthComplete,
        onSwitchToLogin: () {
          setState(() => authMode = 'login');
        },
      );
    }

    // ROLE SELECTION VIEW
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.cyan, Colors.blue, Colors.purple],
                  ).createShader(bounds),
                  child: const Text(
                    "FocusMate",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Choose your account type",
                  style: TextStyle(color: Colors.grey.shade400),
                ),
                const SizedBox(height: 40),

                // ROLE CARDS
                Expanded(
                  child: ListView.builder(
                    itemCount: roles.length,
                    itemBuilder: (context, i) {
                      final role = roles[i];

                      return GestureDetector(
                        onTap: () => handleRoleSelect(role['type']),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: role['bg'].cast<Color>(),
                            ),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // icon + title + description
                              Row(
                                children: [
                                  Container(
                                    height: 55,
                                    width: 55,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: role['color'].cast<Color>(),
                                      ),
                                    ),
                                    child: Icon(
                                      role['icon'],
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          role['title'],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          role['description'],
                                          style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 14),

                              // features
                              GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                itemCount: role['features'].length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisExtent: 20,
                                    ),
                                itemBuilder: (context, idx) {
                                  return Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: role['color'].cast<Color>(),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          role['features'][idx],
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              const SizedBox(height: 20),

                              // button
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: LinearGradient(
                                    colors: role['color'].cast<Color>(),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  "Get Started →",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Footer
                const SizedBox(height: 10),
                Text(
                  "Secure authentication • All data is encrypted",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
