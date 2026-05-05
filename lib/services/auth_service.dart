import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Initialize Supabase. Call once in main() before runApp().
Future<void> initSupabase() async {
  await dotenv.load(fileName: '.env');
  final url = dotenv.env['SUPABASE_URL'] ?? '';
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (url.isEmpty || url.contains('YOUR_PROJECT_ID')) {
    // Supabase not configured yet — skip init, app works offline.
    return;
  }

  await Supabase.initialize(url: url, anonKey: anonKey);
}

/// Whether Supabase is configured and available.
bool get isSupabaseConfigured {
  try {
    Supabase.instance;
    return true;
  } catch (_) {
    return false;
  }
}

/// Convenience getter.
SupabaseClient get supabase => Supabase.instance.client;

// ─────────────────────── Auth State Provider ───────────────────────

class AuthState {
  const AuthState({this.user, this.loading = false, this.error});
  final User? user;
  final bool loading;
  final String? error;

  bool get isLoggedIn => user != null;
  String get displayName =>
      user?.userMetadata?['display_name'] as String? ??
      user?.email?.split('@').first ??
      'User';

  AuthState copyWith({User? user, bool? loading, String? error, bool clearError = false, bool clearUser = false}) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  void _init() {
    if (!isSupabaseConfigured) return;
    final session = supabase.auth.currentSession;
    if (session != null) {
      state = state.copyWith(user: supabase.auth.currentUser);
    }
    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        state = state.copyWith(user: session.user, clearError: true);
      } else {
        state = state.copyWith(clearUser: true);
      }
    });
  }

  Future<void> signUpEmail(String email, String password, {String? displayName}) async {
    if (!isSupabaseConfigured) {
      state = state.copyWith(error: 'Supabase not configured. Add .env credentials.');
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );
      state = state.copyWith(user: res.user, loading: false);
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> signInEmail(String email, String password) async {
    if (!isSupabaseConfigured) {
      state = state.copyWith(error: 'Supabase not configured. Add .env credentials.');
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await supabase.auth.signInWithPassword(email: email, password: password);
      state = state.copyWith(user: res.user, loading: false);
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> signInWithApple() async {
    if (!isSupabaseConfigured) {
      state = state.copyWith(error: 'Supabase not configured.');
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      await supabase.auth.signInWithOAuth(OAuthProvider.apple);
      state = state.copyWith(user: supabase.auth.currentUser, loading: false);
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> signOut() async {
    if (!isSupabaseConfigured) return;
    await supabase.auth.signOut();
    state = const AuthState();
  }

  Future<void> deleteAccount() async {
    if (!isSupabaseConfigured) return;
    state = state.copyWith(loading: true);
    try {
      // Requires a Supabase Edge Function or service_role call.
      // For now call the RPC; set up the function in Supabase dashboard.
      await supabase.rpc('delete_user');
      await supabase.auth.signOut();
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Account deletion failed: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    if (!isSupabaseConfigured) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      await supabase.auth.resetPasswordForEmail(email);
      state = state.copyWith(loading: false);
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
