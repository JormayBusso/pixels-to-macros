import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSignUp = false;
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _nameC = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authProvider.notifier);
    if (_isSignUp) {
      await notifier.signUpEmail(
        _emailC.text.trim(),
        _passC.text,
        displayName: _nameC.text.trim().isNotEmpty ? _nameC.text.trim() : null,
      );
    } else {
      await notifier.signInEmail(_emailC.text.trim(), _passC.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Create Account' : 'Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  _isSignUp ? 'Join Pixels to Macros' : 'Welcome back',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignUp
                      ? 'Create an account to sync your data across devices.'
                      : 'Sign in to access your synced nutrition data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.gray500),
                ),
                const SizedBox(height: 32),

                // Sign in with Apple
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: auth.loading
                        ? null
                        : () => ref.read(authProvider.notifier).signInWithApple(),
                    icon: const Icon(Icons.apple, size: 22),
                    label: const Text('Continue with Apple'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: AppTheme.gray200),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(color: AppTheme.gray400)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                if (_isSignUp) ...[
                  TextFormField(
                    controller: _nameC,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDeco('Display name (optional)'),
                  ),
                  const SizedBox(height: 12),
                ],

                TextFormField(
                  controller: _emailC,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _inputDeco('Email'),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passC,
                  obscureText: true,
                  decoration: _inputDeco('Password'),
                  validator: (v) {
                    if (v == null || v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                if (!_isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        final email = _emailC.text.trim();
                        if (email.contains('@')) {
                          ref.read(authProvider.notifier).resetPassword(email);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password reset email sent')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter your email first')),
                          );
                        }
                      },
                      child: const Text('Forgot password?'),
                    ),
                  ),

                const SizedBox(height: 20),

                if (auth.error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(auth.error!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ),

                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: auth.loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: auth.loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                  ),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Sign up",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppTheme.gray100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
