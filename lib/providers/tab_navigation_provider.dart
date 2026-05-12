import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A provider that the main shell watches to switch tabs programmatically.
/// Set to -1 to indicate no pending navigation.
final tabNavigationProvider = StateProvider<int>((ref) => -1);
