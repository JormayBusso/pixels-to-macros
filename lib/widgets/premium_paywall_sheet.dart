import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/mascot_type.dart';
import '../providers/user_prefs_provider.dart';
import '../services/premium_service.dart';
import '../theme/app_theme.dart';

/// Shows the premium theme paywall. Returns true if premium was unlocked.
///
/// If [selectSeedOnUnlock] is provided, that seed is applied as the active
/// theme once premium is unlocked.
Future<bool> showPremiumPaywall(
  BuildContext context, {
  AppColorSeed? selectSeedOnUnlock,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumPaywallSheet(selectSeedOnUnlock: selectSeedOnUnlock),
  );
  return result ?? false;
}

class _PremiumPaywallSheet extends ConsumerStatefulWidget {
  const _PremiumPaywallSheet({this.selectSeedOnUnlock});

  final AppColorSeed? selectSeedOnUnlock;

  @override
  ConsumerState<_PremiumPaywallSheet> createState() =>
      _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends ConsumerState<_PremiumPaywallSheet> {
  bool _busy = false;

  static const _previewSeeds = [
    AppColorSeed.aiAurora,
    AppColorSeed.midnightNeon,
    AppColorSeed.solarFlare,
    AppColorSeed.emeraldMirage,
    AppColorSeed.royalAmethyst,
    AppColorSeed.geminiAI,
  ];

  Future<void> _grant() async {
    await ref
        .read(userPrefsProvider.notifier)
        .setPremiumUnlocked(true);
    final seed = widget.selectSeedOnUnlock;
    if (seed != null) {
      final prefs = ref.read(userPrefsProvider);
      await ref
          .read(userPrefsProvider.notifier)
          .update(prefs.copyWith(themeColorSeed: seed));
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.premiumUnlockedToast)),
    );
  }

  Future<void> _purchase() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final result = await PremiumService.instance.purchasePremium();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == PremiumPurchaseResult.purchased) {
      await _grant();
    } else if (result == PremiumPurchaseResult.unavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.premiumComingSoon)),
      );
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final result = await PremiumService.instance.restorePurchases();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == PremiumPurchaseResult.purchased) {
      await _grant();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.premiumComingSoon)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = Color(0xFF7C5CFF);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15122B), Color(0xFF0B0A1A)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C5CFF), Color(0xFFFF5FA2)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.workspace_premium,
                        color: Colors.white, size: 27),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.premiumThemesTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.premiumThemesSubtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    for (final seed in _previewSeeds) ...[
                      Expanded(
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                seed.color,
                                Color.alphaBlend(
                                  Colors.black.withValues(alpha: 0.25),
                                  seed.color,
                                ),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _Feature(text: l10n.premiumFeatureAnimated, accent: accent),
              const SizedBox(height: 12),
              _Feature(text: l10n.premiumFeatureGlow, accent: accent),
              const SizedBox(height: 12),
              _Feature(text: l10n.premiumFeaturePacks, accent: accent),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _purchase,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '${l10n.premiumUnlockCta} · ${PremiumService.fallbackPriceLabel}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _restore,
                  child: Text(
                    l10n.premiumRestore,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              if (PremiumService.instance.canDevUnlock)
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : _grant,
                    child: Text(
                      l10n.premiumDevUnlock,
                      style: TextStyle(
                        color: AppTheme.amber500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              Center(
                child: TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: Text(
                    l10n.premiumMaybeLater,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, color: accent, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
