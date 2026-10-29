import 'package:flutter/material.dart';

import '../services/haptic_service.dart';
import '../theme/app_theme.dart';

class OnboardingOverlay extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingOverlay({super.key, required this.onFinished});

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _step = 0;

  static const List<_OnboardingStep> _steps = [
    _OnboardingStep(
      icon: Icons.search,
      title: 'Cari tujuan',
      body: 'Tap kolom pencarian di bawah, ketik nama tempat, lalu pilih.',
    ),
    _OnboardingStep(
      icon: Icons.bluetooth,
      title: 'Connect ke ABOT',
      body: 'Tap chip "Abot belum nyala" di kanan atas untuk pairing.',
    ),
    _OnboardingStep(
      icon: Icons.settings,
      title: 'Atur sesuai selera',
      body: 'Buka pengaturan untuk ubah suara, tema, dan unit jarak.',
    ),
  ];

  Future<void> _next() async {
    await HapticService.select();
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;

    return Container(
      color: Colors.black.withOpacity( 0.75),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Card
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey(_step),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity( 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        step.icon,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      step.body,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface
                            .withOpacity( 0.7),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Progress dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_steps.length, (i) {
                        final active = i == _step;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : AppColors.primary.withOpacity( 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                        ),
                        child: Text(
                          isLast ? 'Mulai!' : 'Lanjut',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    if (!isLast) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: widget.onFinished,
                        child: const Text('Lewati'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}
