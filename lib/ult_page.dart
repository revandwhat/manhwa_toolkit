import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'services/game_service.dart';

class UltCinematicPage extends StatefulWidget {
  const UltCinematicPage({super.key, required this.event});

  final UltEvent event;

  @override
  State<UltCinematicPage> createState() => _UltCinematicPageState();
}

class _UltCinematicPageState extends State<UltCinematicPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..forward();

  late final List<Offset> _stars;
  late final List<double> _phases;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _stars = [
      for (var i = 0; i < 18; i++)
        Offset(0.05 + rng.nextDouble() * 0.9, 0.08 + rng.nextDouble() * 0.84),
    ];
    _phases = [for (var i = 0; i < 18; i++) rng.nextDouble() * 6.28];
    Future.delayed(const Duration(milliseconds: 2650), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final flight = (t / 0.40).clamp(0.0, 1.0);
          final impact = ((t - 0.40) / 0.35).clamp(0.0, 1.0);
          final impacting = t >= 0.40;

          // orb path: from off bottom-left, arcing to center
          final fx = -0.25 + 0.75 * flight;
          final fy =
              0.72 - math.sin(math.pi * flight) * 0.35 - 0.27 * flight;

          return Stack(
            fit: StackFit.expand,
            children: [
              // background
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 0.05),
                    radius: 1.2,
                    colors: impacting
                        ? const [
                            Colors.white,
                            Color(0xFFB388FF),
                            Color(0xFF1A0533),
                          ]
                        : const [
                            Color(0xFF311B92),
                            Color(0xFF150033),
                            Colors.black,
                          ],
                  ),
                ),
              ),

              // floating purple particles
              for (var i = 0; i < _stars.length; i++)
                Positioned(
                  left: size.width * _stars[i].dx,
                  top: size.height * _stars[i].dy,
                  child: Opacity(
                    opacity: (math.sin(t * 6.3 + _phases[i]).abs()) * 0.7,
                    child: Container(
                      width: 3 + (i % 3),
                      height: 3 + (i % 3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFB388FF),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),

              // banner
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: (t / 0.12).clamp(0.0, 1.0),
                  child: Column(
                    children: [
                      Text(
                        widget.event.heroName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFD1B3FF),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          shadows: [
                            Shadow(color: Color(0xFF7B2FF7), blurRadius: 24),
                            Shadow(color: Colors.white, blurRadius: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'U L T I M A T E',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          letterSpacing: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // the projectile
              if (!impacting)
                Positioned(
                  left: size.width * fx - 70,
                  top: size.height * fy - 70,
                  child: _orb(widget.event.assetUrl, 140),
                ),

              // impact rings
              if (impacting)
                for (final frac in const [0.18, 0.30, 0.44, 0.60])
                  Center(
                    child: Container(
                      width: size.shortestSide * 2 * frac * impact,
                      height: size.shortestSide * 2 * frac * impact,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFB388FF)
                              .withValues(alpha: (1 - impact)),
                          width: 5 * (1 - impact) + 1,
                        ),
                      ),
                    ),
                  ),

              // white flash on impact
              if (impacting)
                Container(
                  color: Colors.white
                      .withValues(alpha: (1 - impact) * 0.30),
                ),

              // damage report
              if (impacting)
                Positioned(
                  bottom: 80,
                  left: 24,
                  right: 24,
                  child: Opacity(
                    opacity: ((impact - 0.25) / 0.3).clamp(0.0, 1.0),
                    child: Column(
                      children: [
                        for (final tg in widget.event.targets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${tg.targetName}  -${tg.dmg}'
                              '${tg.ko ? "   K.O." : ""}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: tg.ko
                                    ? Colors.redAccent
                                    : Colors.white,
                                shadows: const [
                                  Shadow(
                                      color: Color(0xFF7B2FF7),
                                      blurRadius: 16),
                                  Shadow(
                                      color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _orb(String? url, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF7B2FF7), blurRadius: 44, spreadRadius: 16),
          BoxShadow(
              color: Colors.deepPurpleAccent,
              blurRadius: 90,
              spreadRadius: 30),
        ],
      ),
      child: (url != null && url.isNotEmpty)
          ? ClipOval(
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _plainOrb()))
          : _plainOrb(),
    );
  }

  Widget _plainOrb() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          Colors.white,
          Color(0xFFB388FF),
          Color(0xFF7B2FF7),
          Color(0xFF311B92),
        ]),
      ),
    );
  }
}
