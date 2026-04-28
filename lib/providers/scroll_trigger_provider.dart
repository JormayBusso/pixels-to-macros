import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Increment this to trigger HomeScreen to scroll to the hydration card.
final scrollToHydrationProvider = StateProvider<int>((ref) => 0);

/// Increment this to trigger SettingsScreen to scroll to the Vacation Mode card.
final scrollToVacationProvider = StateProvider<int>((ref) => 0);
