import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/user_provider.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

class StudyPassScreen extends ConsumerWidget {
  const StudyPassScreen({super.key});

  Future<void> _redeemPass(BuildContext context, WidgetRef ref, int cost, String activity) async {
    final user = ref.read(userProvider).value;
    if (user == null) return;

    if (user.passes < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("You need $cost pass(es) to $activity. You only have ${user.passes}."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Confirm redemption
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Confirm Redemption", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to spend $cost pass(es) to $activity?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
            child: const Text("Redeem"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'passes': FieldValue.increment(-cost),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Success! $activity is now active."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Study Pass", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
        error: (e, _) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.white))),
        data: (user) {
          if (user == null) return const Center(child: Text("User not found", style: TextStyle(color: Colors.white)));

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  width: double.infinity,
                  decoration: AppTheme.cardContainer(AppColors.roleGradients['user']!),
                  child: Column(
                    children: [
                      const Icon(Icons.confirmation_number, size: 48, color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        "Available Passes",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${user.passes}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Earn 1 pass for every 30 mins of focus",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                      ),
                      if (user.minutesTowardsNextPass > 0) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: user.minutesTowardsNextPass / 30,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${30 - user.minutesTowardsNextPass} mins remaining for next pass",
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  "Redeem Passes",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      _buildRedeemOption(
                        context,
                        ref,
                        "Unlock Social Media",
                        "15 minutes access",
                        1,
                        Icons.facebook,
                        "unlock social media",
                      ),
                      _buildRedeemOption(
                        context,
                        ref,
                        "Unlock Games",
                        "30 minutes access",
                        2,
                        Icons.games,
                        "unlock games",
                      ),
                      _buildRedeemOption(
                        context,
                        ref,
                        "Emergency Unlock",
                        "Unlock all apps for 5 mins",
                        3,
                        Icons.warning_amber_rounded,
                        "apply emergency unlock",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRedeemOption(
    BuildContext context,
    WidgetRef ref,
    String title,
    String subtitle,
    int cost,
    IconData icon,
    String activity,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardOverlay,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.cyanAccent),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            "$cost Pass",
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: () => _redeemPass(context, ref, cost, activity),
      ),
    );
  }
}