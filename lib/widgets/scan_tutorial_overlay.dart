import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One-time tutorial overlay shown before the user's first scan.
///
/// Shows 3 quick tips with illustrations, then a "Got it" button.
class ScanTutorialOverlay extends StatefulWidget {
  const ScanTutorialOverlay({super.key, required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<ScanTutorialOverlay> createState() => _ScanTutorialOverlayState();
}

class _ScanTutorialOverlayState extends State<ScanTutorialOverlay> {
  final _controller = PageController();
  int _page = 0;

  static const _tips = [
    _TipData(
      icon: Icons.crop_free,
      title: 'Step 1 — Top View',
      body: 'Hold your phone about 30 cm directly above the plate.\n'
          'Centre the food inside the green reticle.',
    ),
    _TipData(
      icon: Icons.rotate_90_degrees_cw,
      title: 'Step 2 — Side View',
      body: 'Slowly tilt the phone to a 45° side angle.\n'
          'This lets the app estimate food height and volume.',
    ),
    _TipData(
      icon: Icons.auto_awesome,
      title: 'Step 3 — Results',
      body: 'The AI analyses the image in under 3 seconds.\n'
          'You can edit any food item if needed.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'How to Scan',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Quick tutorial — shown only once',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 24),

            // ── Tip pages ──────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _tips.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _TipPage(tip: _tips[i]),
              ),
            ),

            // ── Page dots ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _tips.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? AppTheme.green400 : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Actions ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _page < _tips.length - 1
                        ? () => _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            )
                        : widget.onDismiss,
                    child: Text(
                        _page < _tips.length - 1 ? 'Next' : 'Got it!'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _TipData {
  const _TipData({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _TipPage extends StatelessWidget {
  const _TipPage({required this.tip});
  final _TipData tip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.green600.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppTheme.green400.withOpacity(0.4), width: 2),
            ),
            child: Icon(tip.icon, size: 48, color: AppTheme.green400),
          ),
          const SizedBox(height: 24),
          Text(
            tip.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tip.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
