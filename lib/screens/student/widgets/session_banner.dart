import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/screens/companion/companion_controlled_page.dart';
import 'package:focus_mate/screens/companion/waiting_for_companion_page.dart';

class SessionBanner extends StatelessWidget {
  final Map<String, dynamic> activeSessionData;
  final String userId;

  const SessionBanner({
    super.key,
    required this.activeSessionData,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final status = activeSessionData['status'];
    final sessionId = activeSessionData['id'];
    final isActive = status == 'ACTIVE';

    return GestureDetector(
      onTap: () {
         if (status == 'ACTIVE') {
           Navigator.push(context, MaterialPageRoute(builder: (_) => CompanionControlledPage(sessionId: sessionId, userId: userId)));
         } else if (status == 'REQUESTED') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => WaitingForCompanionPage(sessionId: sessionId, userId: userId)));
         }
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive 
                ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          ),
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: (isActive ? Colors.redAccent : Colors.orangeAccent).withValues(alpha: 0.4),
              blurRadius: 16.r,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(isActive ? Icons.lock_clock : Icons.hourglass_top, color: Colors.white, size: 24.sp),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? "Session Active" : "Waiting for Companion",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.sp),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    isActive ? "Your app access is currently managed." : "Tap to verify your connection status.",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14.sp),
          ],
        ),
      ),
    );
  }
}
