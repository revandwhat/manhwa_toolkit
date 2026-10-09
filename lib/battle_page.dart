
import 'dart:async';

import 'package:flutter/material.dart' hide Hero;

import 'services/game_service.dart';
import 'widgets/glow_border.dart';

class _Fv {
  _Fv(this.max) : hp = max;

  final int max;
  int hp;
  bool alive = true;
  bool shake = false;
  bool lunge = false;
  String? pop;
  int popV = 0;
  String? healPop;
  int healV = 0;
}

class BattlePage extends StatefulWidget {
  const BattlePage({super.key, required this.result});

  final BattleResult result;

  @override
  State<BattlePage> createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> {
  late final Map<String, _Fv> _v;
  int _round = 0;
  int _speed = 1;
  bool _done = false;
  UltEvent? _ult;
  bool _ultFly = false;
  bool _ultHit = false;
  Timer? _closeTimer;
  int _closeLeft = 5;

  static const _heroGlow = Color(0xFF60A5FA);
  static const _enemyGlow = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    _v = {};
    for (final f in widget.result.heroes) {
      _v[f.id] = _Fv(f.maxHp);
    }
    for (final f in widget.result.enemies) {
      _v[f.id] = _Fv(f.maxHp);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  Future<void> _wait(int ms) =>
      Future.delayed(Duration(milliseconds: _speed == 0 ? 1 : ms ~/ _speed));

  Future<void> _play() async {
    await _wait(500);
    for (final e in widget.result.events) {
      if (mounted) setState(() => _round = e.round);
      for (final u in widget.result.ults) {
        if (u.round == e.round) await _playUlt(u);
      }
      for (final h in e.hits) {
        final a = _v[h.attackerId]!;
        final t = _v[h.targetId]!;
        if (mounted) setState(() => a.lunge = true);
        await _wait(140);
        if (mounted) {
          setState(() {
            t.hp = h.targetHpAfter;
            t.shake = true;
            t.popV++;
            t.pop = h.crit ? 'CRIT -${h.dmg}!' : '-${h.dmg}';
            if (h.heal > 0) {
              a.healV++;
              a.healPop = '+${h.heal}';
            }
            if (h.ko) {
              t.alive = false;
              t.pop = 'KO!';
            }
          });
        }
        await _wait(180);
        if (mounted) {
          setState(() {
            a.lunge = false;
            t.shake = false;
          });
        }
        await _wait(120);
      }
    }
    if (mounted) {
      setState(() => _done = true);
      if (widget.result.win) {
        _closeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() => _closeLeft--);
          if (_closeLeft <= 0) {
            t.cancel();
            Navigator.pop(context);
          }
        });
      }
    }
  }

  Color _noteBg(String n) => n.startsWith('Synergy')
      ? const Color(0xFF1E3A8A)
      : n.startsWith('Bulwark')
          ? const Color(0xFF0F2A5C)
          : const Color(0xFFB45309);

  Future<void> _playUlt(UltEvent u) async {
    if (!mounted) return;
    setState(() {
      _ult = u;
      _ultFly = false;
      _ultHit = false;
    });
    await _wait(400);
    if (mounted) setState(() => _ultFly = true);
    await _wait(700);
    if (mounted) {
      setState(() {
        _ultHit = true;
        for (final t in u.targets) {
          final v = _v[t.targetId];
          if (v == null) continue;
          v.hp = t.hpAfter;
          v.shake = true;
          v.popV++;
          v.pop = t.ko ? 'KO!' : '-${t.dmg}';
          if (t.ko) v.alive = false;
        }
      });
    }
    await _wait(900);
    if (mounted) {
      setState(() {
        for (final t in u.targets) {
          _v[t.targetId]?.shake = false;
        }
        _ult = null;
        _ultFly = false;
        _ultHit = false;
      });
    }
    await _wait(250);
  }

  Widget _ultOverlay(UltEvent u) {
    return LayoutBuilder(builder: (ctx, cons) {
      final W = cons.maxWidth;
      final H = cons.maxHeight;
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: const Color(0xFF7B2FF7)
                .withValues(alpha: _ultHit ? 0.10 : 0.30),
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Text(
              '${u.heroName} - ULTIMATE',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD1B3FF),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Color(0xFF7B2FF7), blurRadius: 20),
                ],
              ),
            ),
          ),
          if (!_ultHit)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInCubic,
              left: _ultFly ? W / 2 - 45 : -90,
              top: _ultFly ? H * 0.24 : H * 0.62,
              child: _orb(u.assetUrl, 90),
            ),
          if (_ultHit)
            for (final sz in const [160.0, 260.0, 380.0])
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  builder: (context, t, _) => Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Container(
                      width: sz * (0.3 + 0.7 * t),
                      height: sz * (0.3 + 0.7 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFB388FF),
                            width: 4 * (1 - t) + 1),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      );
    });
  }

  Widget _orb(String? url, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF7B2FF7),
              blurRadius: 40,
              spreadRadius: 14),
          BoxShadow(
              color: Colors.deepPurpleAccent,
              blurRadius: 80,
              spreadRadius: 28),
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

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Floor ${r.floor} - ${r.enemies.length} enemies'),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (r.roomPicture != null)
            Image.network(
              r.roomPicture!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: const Color(0xFF0B1B3A)),
            )
          else
            Container(color: const Color(0xFF0B1B3A)),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          if (_ult != null)
            Positioned.fill(
              child: IgnorePointer(child: _ultOverlay(_ult!)),
            ),
          SafeArea(
            child: Column(
              children: [
                if (r.comboNotes.isNotEmpty)
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final n in r.comboNotes)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: _noteBg(n),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Center(
                                child: Text(n,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('Round $_round',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('ENEMIES',
                              style: TextStyle(
                                  color: _enemyGlow,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Wrap(
                          children: [
                            for (final f in r.enemies)
                              _card(f, _v[f.id]!, _enemyGlow, false),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('VS',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 22)),
                        ),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('YOUR TEAM',
                              style: TextStyle(
                                  color: _heroGlow,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Wrap(
                          children: [
                            for (final f in r.heroes)
                              _card(f, _v[f.id]!,
                                f.star == 6
                                    ? const Color(0xFFE53935)
                                    : (f.star == 7
                                        ? Colors.amber
                                        : _heroGlow), true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_done)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: OutlinedButton(
                      onPressed: () => setState(() => _speed =
                          _speed == 1 ? 2 : (_speed == 2 ? 4 : 0)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white),
                      child:
                          Text(_speed == 0 ? 'Skip >>' : '${_speed}x speed'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: FilledButton(
                      onPressed: () {
                        _closeTimer?.cancel();
                        Navigator.pop(context);
                      },
                      child: Text(r.win
                          ? 'Victory! +${r.coins} coins - $_closeLeft'
                          : 'Defeated... +${r.coins} coins'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(FighterInfo f, _Fv v, Color glow, bool isHero) {
    final frac = v.max <= 0 ? 0.0 : (v.hp / v.max).clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: v.alive ? 1.0 : 0.4,
      child: Transform.translate(
        offset: Offset(v.shake ? 6 : 0,
            isHero ? (v.lunge ? -18.0 : 0) : (v.lunge ? 18.0 : 0)),
        child: GlowBorder(
          color: f.boss ? Colors.deepOrangeAccent : glow,
          width: f.boss ? 2.5 : 1.5,
          radius: 8,
          child: Container(
            width: 96,
            height: 128,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1E3C),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isHero && f.picture != null)
                  Image.network(f.picture!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _bg(glow))
                else
                  _bg(glow),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
                if (f.boss)
                  const Positioned(
                    top: 2,
                    left: 0,
                    right: 0,
                    child: Text('BOSS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.deepOrangeAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                if (!v.alive)
                  const Center(
                    child: Text('KO',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black)
                            ])),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(color: glow, blurRadius: 6),
                                  const Shadow(
                                      color: Colors.black, blurRadius: 3),
                                ])),
                        const SizedBox(height: 2),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 5,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(
                                HSVColor.fromColor(glow)
                                    .withSaturation(1)
                                    .withValue(0.35 + 0.65 * frac)
                                    .toColor()),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Stack(children: [
                          Text('${f.power} atk',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8,
                                  shadows: [
                                    Shadow(color: glow, blurRadius: 4),
                                  ])),
                          if (v.pop != null)
                            Positioned.fill(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('p${v.popV}'),
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 700),
                                builder: (context, t, _) => Opacity(
                                  opacity: (1 - t).clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset(0, -16 * t),
                                    child: Text(
                                      v.pop!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            (v.pop ?? '').startsWith('CRIT')
                                                ? Colors.orange
                                                : ((v.pop ?? '') == 'KO!'
                                                    ? Colors.white
                                                    : (isHero
                                                        ? Colors.redAccent
                                                        : Colors.white)),
                                        shadows: const [
                                          Shadow(
                                              blurRadius: 6,
                                              color: Colors.black)
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (v.healPop != null)
                            Positioned.fill(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('h${v.healV}'),
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 700),
                                builder: (context, t, _) => Opacity(
                                  opacity: (1 - t).clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset(0, -16 * t),
                                    child: Text(
                                      v.healPop!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.greenAccent,
                                        shadows: [
                                          Shadow(
                                              blurRadius: 6,
                                              color: Colors.black)
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bg(Color color) {
    return Container(
      color: const Color(0xFF0F1E3C),
      alignment: Alignment.center,
      child:
          Icon(Icons.catching_pokemon, color: color.withValues(alpha: 0.35)),
    );
  }
}
