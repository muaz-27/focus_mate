import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/auth/login_screen.dart';
import 'package:focus_mate/auth/signup_screen.dart';
import 'package:focus_mate/theme/app_colors.dart';

class AuthScreen extends StatefulWidget {
  final Function(UserRole role, dynamic userData) onAuthComplete;

  const AuthScreen({super.key, required this.onAuthComplete});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  UserRole? selectedRole;
  String authMode = 'select';

  List<Map<String, dynamic>> _getRoles(bool isDark) => [
    {
      'type': UserRole.user,
      'title': 'Student',
      'description': 'Take control of your focus and study habits',
      'color': AppColors.roleGradients['user']!,
      'bg': isDark ? AppColors.roleBackgroundsDark['user']! : AppColors.roleBackgroundsLight['user']!,
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
      'color': AppColors.roleGradients['companion']!,
      'bg': isDark ? AppColors.roleBackgroundsDark['companion']! : AppColors.roleBackgroundsLight['companion']!,
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
      'color': AppColors.roleGradients['parent']!,
      'bg': isDark ? AppColors.roleBackgroundsDark['parent']! : AppColors.roleBackgroundsLight['parent']!,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgGradient = isDark ? AppColors.darkBackgroundGradient : AppColors.lightBackgroundGradient;

    // LOGIN VIEW
    if (authMode == 'login' && selectedRole != null) {
      return Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: LoginScreen(
          role: selectedRole!,
          onBack: backToSelect,
          onLogin: widget.onAuthComplete,
          onSwitchToSignup: () {
            setState(() => authMode = 'signup');
          },
        ),
      );
    }

    // SIGNUP VIEW
    if (authMode == 'signup' && selectedRole != null) {
      return Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SignupScreen(
          role: selectedRole!,
          onBack: backToSelect,
          onSignup: widget.onAuthComplete,
          onSwitchToLogin: () {
            setState(() => authMode = 'login');
          },
        ),
      );
    }

    // ROLE SELECTION VIEW
    return Container(
      decoration: BoxDecoration(
        gradient: bgGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(18.w),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Header
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          AppColors.roleGradients['user']![0],
                          AppColors.roleGradients['companion']![0],
                          AppColors.roleGradients['parent']![0]
                        ],
                      ).createShader(bounds),
                      child: Text(
                        "FocusMate",
                        style: TextStyle(
                          fontSize: 32.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      "Choose your account type",
                      style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, fontSize: 14.sp),
                    ),
                    SizedBox(height: 40.h),

                    // ROLE CARDS
                    Expanded(
                      child: ListView.builder(
                        itemCount: _getRoles(isDark).length,
                        itemBuilder: (context, i) {
                          final role = _getRoles(isDark)[i];
                          final cardTextColor = isDark ? Colors.white : Colors.black87;
                          final cardSubTextColor = isDark ? Colors.white70 : Colors.black54;

                          return GestureDetector(
                            onTap: () => handleRoleSelect(role['type']),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 18.h),
                              padding: EdgeInsets.all(20.w),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16.r),
                                gradient: LinearGradient(
                                  colors: role['bg'].cast<Color>(),
                                ),
                                border: Border.all(
                                  color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10.r,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // icon + title + description
                                  Row(
                                    children: [
                                      Container(
                                        height: 55.w,
                                        width: 55.w,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12.r),
                                          gradient: LinearGradient(
                                            colors: role['color'].cast<Color>(),
                                          ),
                                        ),
                                        child: Icon(
                                          role['icon'],
                                          color: Colors.white,
                                          size: 30.sp,
                                        ),
                                      ),
                                      SizedBox(width: 16.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              role['title'],
                                              style: TextStyle(
                                                color: cardTextColor,
                                                fontSize: 18.sp,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              role['description'],
                                              style: TextStyle(
                                                color: cardSubTextColor,
                                                fontSize: 13.sp,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  SizedBox(height: 14.h),

                                  // features
                                  GridView.builder(
                                    physics: const NeverScrollableScrollPhysics(),
                                    shrinkWrap: true,
                                    itemCount: role['features'].length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          mainAxisExtent: 20.h,
                                          crossAxisSpacing: 8.w,
                                        ),
                                    itemBuilder: (context, idx) {
                                      return Row(
                                        children: [
                                          Container(
                                            width: 6.w,
                                            height: 6.w,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: role['color'].cast<Color>(),
                                              ),
                                              borderRadius: BorderRadius.circular(
                                                50.r,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 6.w),
                                          Expanded(
                                            child: Text(
                                              role['features'][idx],
                                              style: TextStyle(
                                                color: cardSubTextColor,
                                                fontSize: 11.sp,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),

                                  SizedBox(height: 20.h),

                                  // button
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 12.h,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10.r),
                                      gradient: LinearGradient(
                                        colors: role['color'].cast<Color>(),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      "Get Started →",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.sp,
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
                    SizedBox(height: 10.h),
                    Text(
                      "Secure authentication • All data is encrypted",
                      style: TextStyle(color: isDark ? Colors.grey.shade600 : Colors.grey.shade500, fontSize: 11.sp),
                    ),
                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
