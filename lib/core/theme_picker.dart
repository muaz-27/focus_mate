import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/theme_provider.dart';

/// Displays a themed bottom-sheet that lets the user pick [ThemeMode].
///
/// Works from any context that has a [WidgetRef] (ConsumerWidget / ConsumerState).
Future<void> showThemePicker(BuildContext context, WidgetRef ref) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final currentMode = ref.read(themeModeProvider).when(
    data: (mode) => mode,
    loading: () => ThemeMode.system,
    error: (_, __) => ThemeMode.system,
  );

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return _ThemePickerSheet(
        isDark: isDark,
        currentMode: currentMode,
        onSelect: (mode) async {
          Navigator.pop(ctx);
          await ref.read(themeModeProvider.notifier).setTheme(mode);
        },
      );
    },
  );
}

class _ThemePickerSheet extends StatefulWidget {
  final bool isDark;
  final ThemeMode currentMode;
  final void Function(ThemeMode) onSelect;

  const _ThemePickerSheet({
    required this.isDark,
    required this.currentMode,
    required this.onSelect,
  });

  @override
  State<_ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<_ThemePickerSheet> {
  late ThemeMode _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentMode;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;
    final accentColor = widget.isDark ? Colors.cyanAccent : Colors.blueAccent;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: subColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.palette_outlined, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Choose your preferred theme',
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Options
          _ThemeOption(
            icon: Icons.light_mode_rounded,
            label: 'Light',
            subtitle: 'Always use the light theme',
            mode: ThemeMode.light,
            selected: _selected,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            isDark: widget.isDark,
            onTap: () => setState(() => _selected = ThemeMode.light),
          ),
          const SizedBox(height: 12),
          _ThemeOption(
            icon: Icons.dark_mode_rounded,
            label: 'Dark',
            subtitle: 'Always use the dark theme',
            mode: ThemeMode.dark,
            selected: _selected,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            isDark: widget.isDark,
            onTap: () => setState(() => _selected = ThemeMode.dark),
          ),
          const SizedBox(height: 12),
          _ThemeOption(
            icon: Icons.phone_android_rounded,
            label: 'System Default',
            subtitle: 'Follow your device settings',
            mode: ThemeMode.system,
            selected: _selected,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            isDark: widget.isDark,
            onTap: () => setState(() => _selected = ThemeMode.system),
          ),
          const SizedBox(height: 28),

          // Apply button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => widget.onSelect(_selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: widget.isDark ? Colors.black : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Apply',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final ThemeMode mode;
  final ThemeMode selected;
  final Color accentColor;
  final Color textColor;
  final Color subColor;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.mode,
    required this.selected,
    required this.accentColor,
    required this.textColor,
    required this.subColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == mode;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected
            ? accentColor.withValues(alpha: 0.12)
            : (isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? accentColor.withValues(alpha: 0.5)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade200),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.18)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isSelected ? accentColor : subColor,
            size: 22,
          ),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: subColor, fontSize: 12),
        ),
        trailing: isSelected
            ? Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              )
            : Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: subColor.withValues(alpha: 0.4), width: 1.5),
                ),
              ),
      ),
    );
  }
}
