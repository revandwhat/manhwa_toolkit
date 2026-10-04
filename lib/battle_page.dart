
import 'package:flutter/material.dart' hide Hero;

import 'services/game_service.dart';

class _Pop {
  _Pop(this.key, this.text, this.color, this.onEnemySide);

  final UniqueKey key;
  final String text;
  final Color color;
  final bool onEnemySide;
}

class BattlePage extends StatefulWidget {
  const BattlePage({super.key, required this.result});

  final BattleResult result;

  @override
  State<BattlePage> createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> {
  late int _heroHp;
  late int _enemyHp;
  final List<_Pop> _pops = [];
  double _heroLunge = 0;
  double _enemyLunge = 0;
  bool _heroShake = false;
  bool _enemyShake = false;
  int _speed = 1; // 1 | 2 | 4 | 0 (skip)
  bool _done = false;

  int get _heroMax => widget.result.heroPower * 10;
  int get _enemyMax => widget.result.enemyPower * 8;

  @override
  void initState() {
    super.initState();
    _heroHp = _heroMax;
    _enemyHp = _enemyMax;
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  Future<void> _wait(int ms) =>
      Future.delayed(Duration(milliseconds: _speed == 0 ? 1 : ms ~/ _speed));

  void _addPop(String text, Color color, bool onEnemySide) {
    final pop = _Pop(UniqueKey(), text, color, onEnemySide);
    _pops.add(pop);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _pops.remove(pop));
    });
  }

  Future<void> _play() async {
    for (final e in widget.result.events) {
      setState(() => _heroLunge = 1);
      await _wait(150);
      setState(() {
        _enemyHp = e.enemyHp;
        _enemyShake = true;
        _addPop(e.crit ? 'CRIT ${e.heroDmg}!' : '${e.heroDmg}',
            e.crit ? Colors.orange : Colors.white, true);
        if (e.heal > 0) _addPop('+${e.heal}', Colors.greenAccent, false);
      });
      await _wait(120);
      setState(() {
        _heroLunge = 0;
        _enemyShake = false;
      });
      await _wait(240);

      if (e.enemyDmg > 0) {
        setState(() => _enemyLunge = 1);
        await _wait(150);
        setState(() {
          _heroHp = e.heroHp;
          _heroShake = true;
          _addPop('${e.enemyDmg}', Colors.redAccent, false);
        });
        await _wait(120);
        setState(() {
          _enemyLunge = 0;
          _heroShake = false;
        });
        await _wait(240);
      }
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Floor ${r.floor}: ${r.enemyName}'),
        centerTitle: true,
      ),
      body: Container(
        color: const Color(0xFF17131F),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _fighter(
                    name: r.enemyName,
                    sub: '${r.enemyPower} power',
                    hp: _enemyHp,
                    max: _enemyMax,
                    color: Colors.red,
                    shake: _enemyShake,
                    lunge: _enemyLunge,
                    top: true,
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('VS',
                          style: TextStyle(
                              color: Colors.white24,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  _fighter(
                    name: r.heroName,
                    sub: '${r.heroPower} power',
                    hp: _heroHp,
                    max: _heroMax,
                    color: Colors.cyan,
                    shake: _heroShake,
                    lunge: _heroLunge,
                    top: false,
                  ),
                  if (!_done)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: OutlinedButton(
                        onPressed: () => setState(() =>
                            _speed = _speed == 1 ? 2 : (_speed == 2 ? 4 : 0)),
                        child:
                            Text(_speed == 0 ? 'Skip >>' : '${_speed}x speed'),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(r.win
                            ? 'Victory! +${r.coins} coins'
                            : 'Defeated... +${r.coins} coins'),
                      ),
                    ),
                ],
              ),
              for (final p in _pops) _popWidget(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _popWidget(_Pop p) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        key: p.key,
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 850),
        builder: (context, t, _) {
          return Align(
            alignment: Alignment(
                0, p.onEnemySide ? -0.55 - 0.12 * t : 0.55 - 0.12 * t),
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0).toDouble(),
              child: Text(
                p.text,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: p.color,
                  shadows: const [
                    Shadow(blurRadius: 8, color: Colors.black)
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fighter({
    required String name,
    required String sub,
    required int hp,
    required int max,
    required Color color,
    required bool shake,
    required double lunge,
    required bool top,
  }) {
    final frac = max <= 0 ? 0.0 : (hp / max).clamp(0.0, 1.0).toDouble();
    return Transform.translate(
      offset: Offset(0, top ? 60 * lunge : -60 * lunge),
      child: Transform.translate(
        offset: Offset(shake ? 7.0 : 0, 0),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$name  $sub',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  Text('$hp / $max',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(end: frac),
                duration: const Duration(milliseconds: 300),
                builder: (context, v, _) {
                  final c = HSVColor.fromColor(color)
                      .withSaturation(1)
                      .withValue(0.3 + 0.7 * v)
                      .toColor();
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 12,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(c),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
