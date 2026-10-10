import 'package:flutter/material.dart';

import '../core/app_localizations.dart';
import 'dual_photo_capture_overlay.dart' show ScanChromePalette, ScanGuideGeometry;

/// One-time tutorial overlay shown before the user's first scan.
///
/// Three short steps (top view → side view → results), each with a glyph that
/// matches the on-camera guide (circle for the top view, rounded frame for the
/// side view), then a "Got it" button.
class ScanTutorialOverlay extends StatefulWidget {
  const ScanTutorialOverlay({super.key, required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<ScanTutorialOverlay> createState() => _ScanTutorialOverlayState();
}

enum _TipGlyph { circle, frame, model }

class _ScanTutorialOverlayState extends State<ScanTutorialOverlay> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ScanChromePalette.of(context);
    final tips = [
      (
        glyph: _TipGlyph.circle,
        title: '${l10n.scanTutorialStep(1)} · ${l10n.scanTopView}',
        body: l10n.scanTutorialTopBody,
      ),
      (
        glyph: _TipGlyph.frame,
        title: '${l10n.scanTutorialStep(2)} · ${l10n.scanSideView}',
        body: l10n.scanTutorialSideBody,
      ),
      (
        glyph: _TipGlyph.model,
        title: '${l10n.scanTutorialStep(3)} · ${l10n.scanTutorialResults}',
        body: l10n.scanTutorialResultsBody,
      ),
    ];
    final last = _page >= tips.length - 1;

    return Material(
      color: const Color(0xF20B0C0F),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              l10n.scanTutorialTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.scanTutorialSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: tips.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _TipPage(
                  glyph: tips[i].glyph,
                  title: tips[i].title,
                  body: tips[i].body,
                  palette: palette,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                tips.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? palette.accent
                        : Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: Text(
                      l10n.skip,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: last
                        ? widget.onDismiss
                        : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            ),
                    child: Text(last ? l10n.gotIt : l10n.next),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _TipPage extends StatelessWidget {
  const _TipPage({
    required this.glyph,
    required this.title,
    required this.body,
    required this.palette,
  });

  final _TipGlyph glyph;
  final String title;
  final String body;
  final ScanChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final visual = Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: palette.premium
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.28),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: Center(
        child: glyph == _TipGlyph.model
            ? Icon(Icons.view_in_ar_rounded, size: 46, color: palette.accent)
            : CustomPaint(
                size: const Size(64, 64),
                painter: _GuideGlyph(
                  frame: glyph == _TipGlyph.frame,
                  palette: palette,
                ),
              ),
      ),
    );

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.78),
            height: 1.45,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight * 1.4;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 16).clamp(0, double.infinity),
            ),
            child: Center(
              child: wide
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        visual,
                        const SizedBox(width: 28),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: text,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [visual, const SizedBox(height: 22), text],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _GuideGlyph extends CustomPainter {
  _GuideGlyph({required this.frame, required this.palette});

  final bool frame;
  final ScanChromePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final RRect shape;
    if (frame) {
      final w = r * 2;
      final h = w * ScanGuideGeometry.sideHeightFactor;
      shape = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: w, height: h),
        Radius.circular(h * ScanGuideGeometry.sideCornerFactor),
      );
    } else {
      shape = RRect.fromRectAndRadius(
        Rect.fromCircle(center: c, radius: r),
        Radius.circular(r),
      );
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    if (palette.premium) {
      stroke.shader =
          SweepGradient(colors: [...palette.gradient, palette.gradient.first])
              .createShader(shape.outerRect);
    } else {
      stroke.color = palette.accent;
    }
    canvas.drawRRect(shape, stroke);
    // Food blob inside the guide.
    final food = Paint()..color = Colors.white.withValues(alpha: 0.8);
    if (frame) {
      final base = shape.outerRect;
      final path = Path()
        ..moveTo(base.left + base.width * 0.22, base.bottom - 6)
        ..quadraticBezierTo(
          c.dx,
          base.top + 2,
          base.right - base.width * 0.22,
          base.bottom - 6,
        )
        ..close();
      canvas.drawPath(path, food);
    } else {
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 1.0, height: r * 0.8),
        food,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuideGlyph old) =>
      old.frame != frame || old.palette != palette;
}
