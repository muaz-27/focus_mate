import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/screens/study/focus_session_screen.dart';

class SessionSetupScreen extends StatefulWidget {
  final String userId;

  const SessionSetupScreen({super.key, required this.userId});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  String _selectedMode = 'Focused';
  double _duration = 45;
  bool _companionControl = true;
  String? _selectedMaterial;

  final List<String> _modes = ['Focused', 'Pomodoro', 'Deep Work'];
  final List<String> _materials = [
    'Math Notes.pdf',
    'History Chapter 4',
    'Physics Formula Sheet',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey.shade600;
    final cardBg = isDark ? AppColors.cardOverlay : Colors.white.withValues(alpha: 0.85);
    final accentBlue = isDark ? Colors.blueAccent : Colors.blue.shade700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("New Session", style: TextStyle(color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['user']!,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Choose what kind of study session you want
            Text(
              "Session Type",
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _modes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final mode = _modes[index];
                  final isSelected = _selectedMode == mode;
                  return ChoiceChip(
                    label: Text(mode),
                    selected: isSelected,
                    onSelected: (selected) =>
                        setState(() => _selectedMode = mode),
                    selectedColor: accentBlue,
                    backgroundColor: cardBg,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : mutedColor,
                    ),
                    side: BorderSide.none,
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Set how long you want to study for
            Text(
              "Duration (minutes)",
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_duration.toInt()} min",
                  style: TextStyle(
                    color: accentBlue,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _duration,
                    min: 5,
                    max: 120,
                    divisions: 23,
                    activeColor: accentBlue,
                    inactiveColor: isDark ? Colors.grey[800] : Colors.grey.shade300,
                    onChanged: (val) => setState(() => _duration = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Decide if your companion can control this session
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _companionControl
                      ? Colors.greenAccent.withValues(alpha: 0.3)
                      : (isDark ? Colors.white10 : Colors.grey.shade300),
                ),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  "Companion Control",
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  "Allow companion to pause/stop session",
                  style: TextStyle(color: mutedColor),
                ),
                value: _companionControl,
                activeThumbColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _companionControl = val),
              ),
            ),
            const SizedBox(height: 40),

            // Start Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FocusSessionScreen(
                        userId: widget.userId,
                        mode: _selectedMode,
                        durationMinutes: _duration.toInt(),
                      ),
                    ),
                  );
                },
                child: const Text(
                  "START SESSION",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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
