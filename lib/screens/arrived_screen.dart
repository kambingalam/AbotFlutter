import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/haptic_service.dart';
import '../services/tts_service.dart';
import '../services/trip_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/abot_face.dart';
import '../widgets/fade_scale_transition.dart';
import 'home_screen.dart';

class ArrivedScreen extends StatefulWidget {
  const ArrivedScreen({super.key});

  @override
  State<ArrivedScreen> createState() => _ArrivedScreenState();
}

class _ArrivedScreenState extends State<ArrivedScreen>
    with TickerProviderStateMixin {
  bool _spoken = false;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _faceScale;
  late final Animation<double> _faceFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _bodyFade;
  late final Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Face: scale dari 0.4 → 1.0 dengan bounce
    _faceScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );

    _faceFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );

    // Title: fade + slide dari bawah
    _titleFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
    );

    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
          ),
        );

    // Body text
    _bodyFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.5, 0.85, curve: Curves.easeOut),
    );

    // Button
    _buttonFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_spoken) {
      _spoken = true;
      // Delay haptic + TTS sedikit biar sinkron dengan animasi
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) HapticService.success();
      });
      _speakArrival();
    }
  }

  Future<void> _speakArrival() async {
    final manager = context.read<TripManager>();
    final tts = context.read<TtsService>();

    final dest = manager.currentTrip?.destinationName ?? 'tujuan';
    await tts.speakArrived(dest);
  }

  Future<void> _startNewTrip() async {
    await HapticService.tap();
    if (!mounted) return;

    final manager = context.read<TripManager>();
    final navigator = Navigator.of(context);

    await manager.stopTrip();
    if (!mounted) return;

    navigator.pushAndRemoveUntil(
      FadeScalePageRoute(page: const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<TripManager>();
    final dest = manager.currentTrip?.destinationName ?? 'Tujuan';

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(),

              // ============================================================
              // Wajah ABOT happy dengan animasi scale
              // ============================================================
              FadeTransition(
                opacity: _faceFade,
                child: ScaleTransition(
                  scale: _faceScale,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: AbotFace(
                        size: 100,
                        color: AppColors.primary,
                        happy: true,
                        blinkInterval: Duration.zero,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ============================================================
              // Title: "Sampai juga!"
              // ============================================================
              SlideTransition(
                position: _titleSlide,
                child: FadeTransition(
                  opacity: _titleFade,
                  child: Column(
                    children: [
                      const Text(
                        'Sampai juga!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        dest,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // ============================================================
              // Body: "Makasih ya udah jalan bareng Abot."
              // ============================================================
              FadeTransition(
                opacity: _bodyFade,
                child: Text(
                  'Makasih ya udah jalan bareng Abot.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              const Spacer(),

              // ============================================================
              // Reminder + button
              // ============================================================
              FadeTransition(
                opacity: _bodyFade,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pastikan barang bawaan lengkap\ndan pembayaran sudah dilakukan.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ============================================================
              // Button "Trip Baru"
              // ============================================================
              FadeTransition(
                opacity: _buttonFade,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _startNewTrip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh_rounded, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Trip Baru',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
