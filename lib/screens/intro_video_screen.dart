import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen intro video shown at app launch.
///
/// The video fills the entire iPhone screen (BoxFit.cover — no black bars).
/// When playback ends it fades quickly into [nextScreen].
class IntroVideoScreen extends StatefulWidget {
  final Widget nextScreen;
  const IntroVideoScreen({super.key, required this.nextScreen});

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  late final AnimationController _fadeOut;
  late final AnimationController _fadeIn;
  late final AnimationController _zoomController;
  late Animation<double> _zoomAnimation;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();

    _fadeOut = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    // Keep the video visible as soon as the first frame is available.
    _fadeIn = AnimationController(
      vsync: this,
      duration: Duration.zero,
    );
    _fadeIn.value = 1;

    // Zoom animation controller — duration will be updated to match the
    // video's duration once it's known.
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // overridden in _initVideo
    );
    _zoomAnimation = Tween(begin: 0.1, end: 2.0).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.easeOut),
    );

    // video_player on iOS can't resolve asset paths that contain spaces
    // (they are URL-encoded as %20 inside the bundle).  We copy the asset
    // bytes to a temp file with a plain name and play from there instead.
    _initVideo(); // Initialize video
  }

  Future<void> _initVideo() async {
    try {
      // Use the no-space asset so VideoPlayerController.asset works on iOS
      // without copying bytes to disk. This reduces startup latency.
      final ctrl = VideoPlayerController.asset('assets/ptm_enter.mp4');
      _controller = ctrl;
      ctrl.addListener(_onVideoTick);

      await ctrl.setLooping(false);
      await ctrl.initialize();
      if (!mounted) return;

      setState(() {});
      await ctrl.play();

      // Update zoom duration to follow the video (cap to 12s to avoid
      // excessively long zooms on long videos). Use 90% of the video
      // duration for the zoom so the final frame can be visible before
      // we fade out.
      final vidDur = ctrl.value.duration;
      final zoomDur = Duration(
          milliseconds:
              (vidDur.inMilliseconds * 0.9).clamp(400, 12000).toInt());
      _zoomController.duration = zoomDur;
      _zoomAnimation = Tween(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _zoomController, curve: Curves.easeOut),
      );

      await _zoomController.forward();
    } catch (_) {
      if (mounted) _navigateNow();
    }
  }

  void _onVideoTick() {
    final ctrl = _controller;
    if (ctrl == null || _navigating || !ctrl.value.isInitialized) return;

    if (ctrl.value.hasError) {
      _finishWithFade();
      return;
    }

    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;

    if (dur > Duration.zero && !ctrl.value.isPlaying && pos >= dur) {
      _finishWithFade();
    }
  }

  void _finishWithFade() {
    if (_navigating) return;
    _navigating = true;
    _fadeOut.forward().then((_) {
      if (mounted) _navigateNow();
    });
  }

  void _navigateNow() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.nextScreen,
        transitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    _fadeOut.dispose();
    _fadeIn.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // MUST stay black to match LaunchScreen.storyboard's black background
      // and the intro video's first frame — otherwise users see a white
      // flash between OS launch and the video's first painted frame.
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video ────────────────────────────────────────────────
          // Rebuild whenever the controller emits a new value.
          if (_controller != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller!,
              builder: (context, value, _) {
                if (!value.isInitialized) return const SizedBox.shrink();

                // aspect ratio handled by FittedBox; no local variable needed

                // Video fills the full screen from the start (cover).
                // The zoom animation scales it further so sides go off-screen.
                return FadeTransition(
                  opacity: _fadeIn,
                  child: AnimatedBuilder(
                    animation: _zoomController,
                    builder: (_, __) => Transform.scale(
                      scale: _zoomAnimation.value,
                      alignment: Alignment.center,
                      child: SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: value.size.width,
                            height: value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // ── Fade-out overlay ─────────────────────────────────────
          AnimatedBuilder(
            animation: _fadeOut,
            builder: (_, __) => IgnorePointer(
              child: Opacity(
                opacity: _fadeOut.value,
                child: const ColoredBox(
                  color: Colors.white,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
