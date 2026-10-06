
import 'package:flutter/material.dart' hide Hero;

import 'services/game_service.dart';

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

  @override
  void initState() {
    super.initState();
    _v = {};
    for (final f in widget.result.heroes) {
      _v[f.id] = _Fv(f.power * 6);
    }
    for (final f in widget.result.enemies) {
      _v[f.id] = _Fv(f.power * 6);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  Future<void> _wait(int ms) =>
      Future.delayed(Duration(milliseconds: _speed == 0 ? 1 : ms ~/ _speed));

  Future<void> _play() async {
    await _wait(500);
    for (final e in widget.result.events) {
      if (mounted) setState(() => _round = e.round);
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
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Floor ${r.floor} - ${r.enemies.length} enemies'),
        centerTitle: true,
      ),
      body: Container(
        color: const Color(0xFF17131F),
        child: SafeArea(
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
                          child: Chip(
                            label: Text(n,
                                style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
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
                                color: Colors.redAccent, fontSize: 11)),
                      ),
                      Wrap(
                        children: [
                          for (final f in r.enemies)
                            _card(f, _v[f.id]!, Colors.red, false),
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
                                color: Colors.cyanAccent, fontSize: 11)),
                      ),
                      Wrap(
                        children: [
                          for (final f in r.heroes)
                            _card(f, _v[f.id]!, Colors.cyan, true),
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
                    onPressed: () => setState(() =>
                        _speed = _speed == 1 ? 2 : (_speed == 2 ? 4 : 0)),
                    child: Text(_speed == 0 ? 'Skip >>' : '${_speed}x speed'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(r.win
                        ? 'Victory! +${r.coins} coins'
                        : 'Defeated... +${r.coins} coins'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(FighterInfo f, _Fv v, Color color, bool isHero) {
    final frac = v.max <= 0 ? 0.0 : (v.hp / v.max).clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: v.alive ? 1.0 : 0.35,
      child: Transform.translate(
        offset: Offset(v.shake ? 6 : 0, isHero ? (v.lunge ? -18.0 : 0) : (v.lunge ? 18.0 : 0)),
        child: Container(
          width: 92,
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(
                color: v.alive ? color.withValues(alpha: 0.5) : Colors.white12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 80,
                    height: 56,
                    child: (isHero && f.picture != null)
                        ? Image.network(
                            f.picture!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                _fallbackAvatar(f, color),
                          )
                        : _fallbackAvatar(f, color),
                  ),
                ),
                if (!v.alive)
                  const Positioned.fill(
                    child: Center(
                      child: Text('KO',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black)
                              ])),
                    ),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9)),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 5,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                      HSVColor.fromColor(color)
                          .withSaturation(1)
                          .withValue(0.3 + 0.7 * frac)
                          .toColor()),
                ),
              ),
              Stack(children: [
                Text('${v.hp}',
                    style: const TextStyle(color: Colors.white70, fontSize: 9)),
                if (v.pop != null)
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('p${v.popV}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      builder: (context, t, _) => Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -14 * t),
                          child: Text(
                            v.pop!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: (v.pop ?? '').startsWith('CRIT')
                                  ? Colors.orange
                                  : ((v.pop ?? '') == 'KO!'
                                      ? Colors.white
                                      : (isHero
                                          ? Colors.redAccent
                                          : Colors.white)),
                              shadows: const [
                                Shadow(blurRadius: 6, color: Colors.black)
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
                          offset: Offset(0, -14 * t),
                          child: Text(
                            v.healPop!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black)
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
    );
  }

  Widget _fallbackAvatar(FighterInfo f, Color color) {
    return Container(
      width: 80,
      height: 56,
      color: color.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        isHeroAvatar(f) ? '★${f.star}' : f.name.characters.first,
        style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  bool isHeroAvatar(FighterInfo f) => f.star > 0;
}
