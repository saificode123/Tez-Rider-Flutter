import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cnic_document_screen.dart';
import '../theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../services/account_access.dart';

class SplashScreen extends StatefulWidget {
  final bool showCyclist;
  const SplashScreen({super.key, this.showCyclist = true});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _dotsCtrl;
  late AnimationController _cyclistCtrl;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _textFade;
  late Animation<double> _pulse;
  late Animation<double> _dotsFade;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // 2.8 s per crossing; repeat keeps the cyclist looping for the full splash duration.
    _cyclistCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _logoScale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);

    _pulse = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _dotsFade = CurvedAnimation(parent: _dotsCtrl, curve: Curves.easeIn);

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _logoCtrl.forward();
    if (widget.showCyclist) _cyclistCtrl.repeat(reverse: false);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _dotsCtrl.forward();
    // Minimum 2.8s so animation is always fully visible before navigating
    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) _checkSession();
  }

  Future<void> _checkSession() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      try {
        if (Get.isRegistered<AuthController>() &&
            !await Get.find<AuthController>().enforceAccountAccess()) {
          if (mounted) {
            Get.offAllNamed(
              '/login',
              arguments: {
                'account_message':
                    'Account access could not be verified. Check your connection and Retry.',
              },
            );
          }
          return;
        }
        // Verify the saved identity and approval with the server before restoring
        // rider presence. Metadata alone cannot authorize a dashboard session.
        final identity = await client.auth.getUser().timeout(
          const Duration(seconds: 8),
        );
        final account = identity.user;
        if (account != null) {
          final profile = await client
              .from('users')
              .select('role,verification_status,is_blocked,rejection_reason')
              .eq('auth_user_id', account.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));
          if (!mounted || account.id != client.auth.currentUser?.id) return;
          final access = AccountAccess.fromProfile(profile);
          if (access.dashboardRoute != null) {
            Get.offAllNamed(access.dashboardRoute!);
          } else if (access.role == 'rider') {
            Get.offAll(() => const CnicDocumentScreen());
          } else {
            Get.offAllNamed(
              '/pending_verification',
              arguments: {
                'status': access.status,
                'reason': profile?['rejection_reason'],
              },
            );
          }
          return;
        }
      } catch (_) {
        // An unavailable or invalid session must not imply successful recovery.
      }
    }
    if (!mounted) return;
    Get.offAllNamed('/login');
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _pulseCtrl.dispose();
    _dotsCtrl.dispose();
    _cyclistCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.gradientDark,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -80,
              right: -80,
              child: _decorCircle(240, Colors.white.withValues(alpha: 0.04)),
            ),
            Positioned(
              bottom: -120,
              left: -80,
              child: _decorCircle(300, Colors.white.withValues(alpha: 0.03)),
            ),
            Positioned(
              top: 160,
              left: -40,
              child: _decorCircle(
                120,
                AppColors.primaryLight.withValues(alpha: 0.12),
              ),
            ),

            if (widget.showCyclist)
              AnimatedBuilder(
                animation: _cyclistCtrl,
                builder: (ctx, child) {
                  final sw = MediaQuery.of(ctx).size.width;
                  final t = Curves.linear.transform(_cyclistCtrl.value);
                  final dx = -220.0 + t * (sw + 240.0);
                  return Positioned(bottom: 90, left: dx, child: child!);
                },
                child: Lottie.asset(
                  'assets/lottie/delivery_cyclist.json',
                  width: 220,
                  height: 180,
                  fit: BoxFit.contain,
                  repeat: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: ScaleTransition(
                      scale: _pulse,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primaryLight.withValues(
                                  alpha: 0.3,
                                ),
                                width: 1.5,
                              ),
                            ),
                          ),
                          Container(
                            width: 136,
                            height: 136,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                          ),
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF388E3C),
                                  AppColors.primaryLight,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryLight.withValues(
                                    alpha: 0.45,
                                  ),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.delivery_dining_rounded,
                                size: 52,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        Text(
                          "TEZRIDER".tr,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            shadows: [
                              Shadow(
                                color: AppColors.primaryLight.withValues(
                                  alpha: 0.6,
                                ),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                          child: Text(
                            "Delivering Excellence, Every Time".tr,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 80),

                FadeTransition(opacity: _dotsFade, child: const _LoadingDots()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      )..repeat(reverse: true, period: Duration(milliseconds: 900 + i * 150)),
    );
    _animations = _controllers
        .map(
          (c) => Tween<double>(
            begin: 0.3,
            end: 1.0,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();

    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _animations[i],
          builder: (_, __) => Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: _animations[i].value),
            ),
          ),
        ),
      ),
    );
  }
}
