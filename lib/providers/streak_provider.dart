import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';

/// Tracks consecutive-day scanning streaks.
class StreakState {
  final int currentStreak;
  final int longestStreak;
  final bool scannedToday;

  const StreakState({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.scannedToday = false,
  });
}

class StreakNotifier extends StateNotifier<StreakState> {
  StreakNotifier() : super(const StreakState());

  Future<void> load() async {
    final scans = await DatabaseService.instance.getAllScanResults();
    if (scans.isEmpty) {
      state = const StreakState();
      return;
    }

    // Collect unique scan dates
    final dates = <DateTime>{};
    for (final scan in scans) {
      final d = scan.timestamp;
      dates.add(DateTime(d.year, d.month, d.day));
    }

    final sorted = dates.toList()..sort((a, b) => b.compareTo(a)); // newest first
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));

    final scannedToday = sorted.isNotEmpty && sorted.first == todayDate;

    // Calculate current streak (consecutive days ending today or yesterday)
    int current = 0;
    DateTime checkDate =
        scannedToday ? todayDate : yesterday;

    for (final date in sorted) {
      if (date == checkDate) {
        current++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (date.isBefore(checkDate)) {
        break;
      }
    }

    // If streak doesn't start from today or yesterday, it's broken
    if (!scannedToday && (sorted.isEmpty || sorted.first != yesterday)) {
      current = 0;
    }

    // Calculate longest streak ever
    int longest = 0;
    int streak = 1;
    final ascending = sorted.reversed.toList();
    for (int i = 1; i < ascending.length; i++) {
      final diff = ascending[i].difference(ascending[i - 1]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        longest = streak > longest ? streak : longest;
        streak = 1;
      }
    }
    longest = streak > longest ? streak : longest;

    state = StreakState(
      currentStreak: current,
      longestStreak: longest,
      scannedToday: scannedToday,
    );
  }
}

final streakProvider = StateNotifierProvider<StreakNotifier, StreakState>(
  (ref) => StreakNotifier(),
);
