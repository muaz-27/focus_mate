import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

/// Standard feedback screen where users can submit feedback.
///
/// Composes an email with subject, category, and body, then opens
/// the user's default email client via [url_launcher].
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  String _selectedCategory = 'General';
  bool _isSending = false;

  static const String _feedbackEmail = 'appfocusmate@gmail.com';

  static const List<String> _categories = [
    'General',
    'Bug Report',
    'Feature Request',
    'UI / Design',
    'Performance',
    'Other',
  ];

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final subject = Uri.encodeComponent(
      '[Focus Mate Feedback] [$_selectedCategory] ${_subjectController.text}',
    );
    final body = Uri.encodeComponent(
      '${_bodyController.text}\n\n---\nCategory: $_selectedCategory\nSent from Focus Mate App',
    );

    final mailtoUri = Uri.parse('mailto:$_feedbackEmail?subject=$subject&body=$body');

    try {
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Email client opened. Send your feedback!'),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No email app found. Please install an email app or send feedback to appfocusmate@gmail.com'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121218) : const Color(0xFFF5F6FA);
    final cardColor = isDark
        ? const Color(0xFF1E1E2E).withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.95);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subTextColor = isDark ? Colors.white54 : Colors.black45;
    final accentColor = isDark ? Colors.cyanAccent : const Color(0xFF5B8DEF);
    final borderColor = isDark ? Colors.white12 : Colors.black12;
    final fieldFillColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade50;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor, size: 20.sp),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Send Feedback',
          style: TextStyle(
            color: textColor,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header illustration area
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 24.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor.withValues(alpha: 0.15),
                        accentColor.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.feedback_outlined,
                        size: 48.sp,
                        color: accentColor,
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        'We value your feedback!',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.w),
                        child: Text(
                          'Help us improve Focus Mate by sharing your thoughts, reporting bugs, or suggesting new features.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 13.sp,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24.h),

                // Category selector
                Text(
                  'Category',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: borderColor),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      icon: Icon(Icons.keyboard_arrow_down, color: subTextColor),
                      style: TextStyle(color: textColor, fontSize: 15.sp),
                      items: _categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Row(
                            children: [
                              Icon(
                                _categoryIcon(category),
                                size: 18.sp,
                                color: accentColor,
                              ),
                              SizedBox(width: 10.w),
                              Text(category),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _selectedCategory = value);
                      },
                    ),
                  ),
                ),

                SizedBox(height: 20.h),

                // Subject field
                Text(
                  'Subject',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                TextFormField(
                  controller: _subjectController,
                  style: TextStyle(color: textColor, fontSize: 15.sp),
                  decoration: InputDecoration(
                    hintText: 'Brief summary of your feedback',
                    hintStyle: TextStyle(color: subTextColor, fontSize: 14.sp),
                    filled: true,
                    fillColor: fieldFillColor,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a subject';
                    }
                    return null;
                  },
                ),

                SizedBox(height: 20.h),

                // Message field
                Text(
                  'Message',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8.h),
                TextFormField(
                  controller: _bodyController,
                  style: TextStyle(color: textColor, fontSize: 15.sp),
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: 'Describe your feedback in detail...',
                    hintStyle: TextStyle(color: subTextColor, fontSize: 14.sp),
                    filled: true,
                    fillColor: fieldFillColor,
                    counterStyle: TextStyle(color: subTextColor, fontSize: 11.sp),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your feedback message';
                    }
                    if (value.trim().length < 10) {
                      return 'Please provide at least 10 characters';
                    }
                    return null;
                  },
                ),

                SizedBox(height: 28.h),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52.h,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _submitFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      disabledBackgroundColor: accentColor.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      elevation: 0,
                    ),
                    child: _isSending
                        ? SizedBox(
                            width: 22.sp,
                            height: 22.sp,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded, size: 20.sp),
                              SizedBox(width: 8.w),
                              Text(
                                'Send Feedback',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                SizedBox(height: 16.h),

                // Alternative contact info
                Center(
                  child: Text(
                    'Or email us directly at $_feedbackEmail',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 12.sp,
                    ),
                  ),
                ),

                SizedBox(height: 20.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Bug Report':
        return Icons.bug_report_outlined;
      case 'Feature Request':
        return Icons.lightbulb_outline;
      case 'UI / Design':
        return Icons.palette_outlined;
      case 'Performance':
        return Icons.speed_outlined;
      case 'Other':
        return Icons.more_horiz;
      case 'General':
      default:
        return Icons.chat_bubble_outline;
    }
  }
}
