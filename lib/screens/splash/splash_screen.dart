import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:focus_mate/core/auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _loadingCtrl;
  late AnimationController _rayCtrl;

  late Animation<double> _fadeIn;
  late Animation<double> _scaleOwl;
  late Animation<double> _pulseAnim;
  late Animation<double> _loadingAnim;
  late Animation<double> _textSlide;

  @override
  void initState() {
    super.initState();
    _mainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _rayCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _loadingCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

    _fadeIn = CurvedAnimation(parent: _mainCtrl, curve: Curves.easeIn);
    _scaleOwl = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: Curves.elasticOut));
    _textSlide = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadingAnim = CurvedAnimation(parent: _loadingCtrl, curve: Curves.easeInOut);

    _mainCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _loadingCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 3800), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AuthGate(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ));
      }
    });
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _pulseCtrl.dispose();
    _rayCtrl.dispose();
    _loadingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF060D1F), // very dark navy
              Color(0xFF091830), // deep navy
              Color(0xFF0B2855), // midnight blue
              Color(0xFF0A3D72), // dark blue accent
            ],
            stops: [0.0, 0.3, 0.65, 1.0],
          ),
        ),
        child: Stack(
          children: [
            CustomPaint(
              size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
              painter: _GeometricPainter(),
            ),
            FadeTransition(
              opacity: _fadeIn,
              child: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    // Owl + rays + orbiting icons
                    SizedBox(
                      width: 280.w,
                      height: 280.w,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Glow circle
                          Container(
                            width: 160.w,
                            height: 160.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00C9FF).withValues(alpha: 0.15),
                                  blurRadius: 60,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                          ),
                          // Rotating rays
                          AnimatedBuilder(
                            animation: _rayCtrl,
                            builder: (_, __) => Transform.rotate(
                              angle: _rayCtrl.value * 2 * pi,
                              child: CustomPaint(size: Size(230.w, 230.w), painter: _RayPainter()),
                            ),
                          ),
                          // Orbiting icons
                          ..._buildOrbitingIcons(),
                          // Owl
                          AnimatedBuilder(
                            animation: Listenable.merge([_scaleOwl, _pulseAnim]),
                            builder: (_, __) => Transform.scale(
                              scale: _scaleOwl.value * _pulseAnim.value,
                              child: SizedBox(
                                width: 110.w, height: 110.w,
                                child: CustomPaint(painter: _OwlPainter()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // App name
                    AnimatedBuilder(
                      animation: _textSlide,
                      builder: (_, __) => Transform.translate(
                        offset: Offset(0, _textSlide.value),
                        child: Column(
                          children: [
                            Text(
                              'FocusMate',
                              style: GoogleFonts.outfit(
                                fontSize: 38.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                                shadows: [
                                  Shadow(color: const Color(0xFF00C9FF).withValues(alpha: 0.5), blurRadius: 16),
                                ],
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'Boost your productivity, together.',
                              style: GoogleFonts.outfit(
                                fontSize: 13.5.sp,
                                color: Colors.white.withValues(alpha: 0.7),
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(height: 16.h),
                            // Role badges row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildRoleBadge(Icons.school_rounded, 'Student', const Color(0xFF00C9FF)),
                                SizedBox(width: 10.w),
                                _buildRoleBadge(Icons.people_rounded, 'Companion', const Color(0xFFAB7CFF)),
                                SizedBox(width: 10.w),
                                _buildRoleBadge(Icons.family_restroom_rounded, 'Parent', const Color(0xFFFF7C7C)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(flex: 2),
                    // Bottom feature labels
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.w),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildFeatureLabel(Icons.family_restroom_rounded, 'Parental\nGuidance'),
                          _buildFeatureLabel(Icons.lock_rounded, 'Security\n& Locks'),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.h),
                    // Loading bar
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.w),
                      child: AnimatedBuilder(
                        animation: _loadingAnim,
                        builder: (_, __) => Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4.r),
                              child: LinearProgressIndicator(
                                value: _loadingAnim.value,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C9FF)),
                                minHeight: 2.5,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'Loading...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10.sp,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 28.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(IconData icon, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12.sp),
          SizedBox(width: 4.w),
          Text(label, style: TextStyle(color: color, fontSize: 11.sp, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _buildOrbitingIcons() {
    const items = [
      _OrbitIcon(Icons.timer_rounded, Color(0xFFFF6B6B), -pi / 3),
      _OrbitIcon(Icons.calendar_month_rounded, Color(0xFF4ECDC4), 0.0),
      _OrbitIcon(Icons.check_box_rounded, Color(0xFF69D2E7), pi / 3),
      _OrbitIcon(Icons.lightbulb_rounded, Color(0xFFFFD93D), pi * 2 / 3),
      _OrbitIcon(Icons.coffee_rounded, Color(0xFFFF9A3C), pi),
      _OrbitIcon(Icons.key_rounded, Color(0xFFA8E6CF), -pi * 2 / 3),
    ];
    return items.map((item) {
      final radius = 115.0.w;
      final x = radius * cos(item.angle);
      final y = radius * sin(item.angle);
      return Transform.translate(
        offset: Offset(x, y),
        child: Container(
          width: 42.w, height: 42.w,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            boxShadow: [BoxShadow(color: item.color.withValues(alpha: 0.25), blurRadius: 10, spreadRadius: 1)],
          ),
          child: Icon(item.icon, color: item.color, size: 22.sp),
        ),
      );
    }).toList();
  }

  Widget _buildFeatureLabel(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 20.sp),
        ),
        SizedBox(height: 5.h),
        Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10.sp, height: 1.3)),
      ],
    );
  }
}

class _OrbitIcon {
  final IconData icon;
  final Color color;
  final double angle;
  const _OrbitIcon(this.icon, this.color, this.angle);
}

// ── Geometric background ──
class _GeometricPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.03)..style = PaintingStyle.fill;
    final stroke = Paint()..color = Colors.white.withValues(alpha: 0.05)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    void drawDiamond(double cx, double cy, double s, {bool filled = false}) {
      final path = Path()
        ..moveTo(cx, cy - s)
        ..lineTo(cx + s * 0.6, cy)
        ..lineTo(cx, cy + s)
        ..lineTo(cx - s * 0.6, cy)
        ..close();
      canvas.drawPath(path, filled ? fill : stroke);
    }
    drawDiamond(size.width * 0.08, size.height * 0.12, 60, filled: true);
    drawDiamond(size.width * 0.88, size.height * 0.08, 50);
    drawDiamond(size.width * 0.95, size.height * 0.42, 38, filled: true);
    drawDiamond(size.width * 0.04, size.height * 0.68, 32);
    drawDiamond(size.width * 0.92, size.height * 0.82, 55, filled: true);
    drawDiamond(size.width * 0.28, size.height * 0.04, 28);
    drawDiamond(size.width * 0.72, size.height * 0.96, 44);
    drawDiamond(size.width * 0.12, size.height * 0.44, 22, filled: true);
    drawDiamond(size.width * 0.78, size.height * 0.55, 20, filled: true);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Ray painter ──
class _RayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const rayCount = 14;
    const halfAngle = 0.055;
    for (int i = 0; i < rayCount; i++) {
      final angle = (i * 2 * pi) / rayCount;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.2), Colors.white.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + size.width / 2 * cos(angle - halfAngle), center.dy + size.height / 2 * sin(angle - halfAngle))
        ..lineTo(center.dx + size.width / 2 * cos(angle + halfAngle), center.dy + size.height / 2 * sin(angle + halfAngle))
        ..close();
      canvas.drawPath(path, paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Owl painter ──
class _OwlPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    // Body
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.68), width: w * 0.78, height: h * 0.62),
        Paint()..color = const Color(0xFF1A8070));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.72), width: w * 0.38, height: h * 0.38),
        Paint()..color = const Color(0xFF5BC4B4));
    // Head
    canvas.drawCircle(Offset(cx, h * 0.38), w * 0.38, Paint()..color = const Color(0xFF0D2440));
    // Cheek patches
    canvas.drawCircle(Offset(cx - w * 0.22, h * 0.43), w * 0.13, Paint()..color = const Color(0xFF1A8070));
    canvas.drawCircle(Offset(cx + w * 0.22, h * 0.43), w * 0.13, Paint()..color = const Color(0xFF1A8070));
    // Ear tufts
    void drawEar(double ex, bool left) {
      final sign = left ? -1.0 : 1.0;
      canvas.drawPath(Path()
        ..moveTo(ex, h * 0.12)
        ..lineTo(ex + sign * w * 0.12, h * 0.01)
        ..lineTo(ex + sign * w * 0.2, h * 0.12)
        ..close(), Paint()..color = const Color(0xFF0D2440));
    }
    drawEar(cx - w * 0.18, true);
    drawEar(cx + w * 0.06, false);
    // Eyes
    void drawEye(double ex, double ey) {
      canvas.drawCircle(Offset(ex, ey), w * 0.14, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(ex, ey), w * 0.13, Paint()..color = const Color(0xFF00C9FF));
      canvas.drawCircle(Offset(ex, ey), w * 0.09, Paint()..color = const Color(0xFF060D1F));
      canvas.drawCircle(Offset(ex - w * 0.03, ey - w * 0.03), w * 0.035, Paint()..color = Colors.white);
    }
    drawEye(cx - w * 0.14, h * 0.36);
    drawEye(cx + w * 0.14, h * 0.36);
    // Beak
    canvas.drawPath(Path()
      ..moveTo(cx - w * 0.055, h * 0.455)
      ..lineTo(cx, h * 0.53)
      ..lineTo(cx + w * 0.055, h * 0.455)
      ..close(), Paint()..color = const Color(0xFFFFB347));
    // Headphones
    final hpPaint = Paint()
      ..color = const Color(0xFF0D2440)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.065
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, h * 0.3), width: w * 0.88, height: h * 0.44),
      pi, pi, false, hpPaint);
    canvas.drawCircle(Offset(cx - w * 0.44, h * 0.3), w * 0.09, Paint()..color = const Color(0xFF0D2440));
    canvas.drawCircle(Offset(cx + w * 0.44, h * 0.3), w * 0.09, Paint()..color = const Color(0xFF0D2440));
    canvas.drawCircle(Offset(cx - w * 0.44, h * 0.3), w * 0.05, Paint()..color = const Color(0xFF00C9FF));
    canvas.drawCircle(Offset(cx + w * 0.44, h * 0.3), w * 0.05, Paint()..color = const Color(0xFF00C9FF));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
