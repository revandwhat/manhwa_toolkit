import 'package:flutter/material.dart' hide Hero;

import 'services/game_service.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final _game = GameService();

  int _coins = 0;
  int _streak = 0;
  int _floor = 0;
  List<Hero> _roster = [];
  bool _claimedToday = false;
  bool _busy = false;
  List<String> _battleLog = [];

  static const _starColor = {
    1: Colors.grey,
    2: Colors.green,
    3: Colors.blue,
    4: Colors.purple,
    5: Colors.amber,
  };
  static const _starLabel = {1: '1*', 2: '2*', 3: '3*', 4: '4*', 5: '5*'};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final coins = await _game.coins();
    final roster = await _game.roster();
    final floor = await _game.floor();
    final streak = await _game.streakDays();
    final last = await _game.claimDaily();
    if (!mounted) return;
    setState(() {
      _coins = coins;
      _roster = roster;
      _floor = floor;
      _streak = streak;
      _claimedToday = last == -1;
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _claim() async {
    final r = await _game.claimDaily();
    if (!mounted) return;
    if (r == -1) {
      _snack('Already claimed today - come back tomorrow');
    } else {
      _snack('+$r coins! Streak bonus included');
    }
    await _refresh();
  }

  Future<void> _gacha(int count) async {
    setState(() => _busy = true);
    try {
      final results = await _game.pull(count, guarantee3: count == 10);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(count == 10 ? '10x Pull!' : 'Single Pull'),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count == 10 ? 5 : 1,
                childAspectRatio: 0.7,
              ),
              itemCount: results.length,
              itemBuilder: (ctx, i) {
                final r = results[i];
                final c = _starColor[r.hero.star]!;
                return Card(
                  color: c.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: c, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_starLabel[r.hero.star]!,
                            style: TextStyle(
                                color: c, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          r.hero.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text('${r.hero.power} pw',
                            style: const TextStyle(fontSize: 10)),
                        if (r.isDupe)
                          const Text('dupe +coins',
                              style:
                                  TextStyle(fontSize: 9, color: Colors.red)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Nice'),
            ),
          ],
        ),
      );
      await _refresh();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Hero? get _strongest {
    if (_roster.isEmpty) return null;
    Hero best = _roster.first;
    for (final h in _roster) {
      if (h.power > best.power) best = h;
    }
    return best;
  }

  Future<void> _battle() async {
    final hero = _strongest;
    if (hero == null) {
      _snack('Pull some heroes first!');
      return;
    }
    setState(() {
      _busy = true;
      _battleLog = [];
    });
    try {
      final r = await _game.battle(hero);
      for (final line in r.log) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() => _battleLog.add(line));
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.monetization_on, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text('$_coins coins',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                Text('Streak: $_streak day(s)'),
              ],
            ),
          ),
        ),
        _card('Daily reward', [
          Text(_claimedToday
              ? 'Claimed today. Come back tomorrow - keep the streak!'
              : 'Claim 200 coins + streak bonus (+50/day, up to +300).'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _claim,
            icon: const Icon(Icons.redeem),
            label: Text(_claimedToday ? 'Claimed' : 'Claim daily reward'),
          ),
        ]),
        _card('Gacha - summon heroes', [
          const Text(
            '1 star to 5 star. Rates: 1* 40%, 2* 30%, 3* 20%, 4* 8%, 5* 2%. '
            'Duplicates convert to coins automatically.',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _gacha(1),
                icon: const Icon(Icons.looks_one),
                label: const Text('1x - 100'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _gacha(10),
                icon: const Icon(Icons.looks_one),
                label: const Text('10x - 900 (3*+ guaranteed)'),
              ),
            ),
          ]),
        ]),
        _card('Roster (${_roster.length})', [
          if (_roster.isEmpty)
            const Text('No heroes yet - go pull!'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _roster)
                Chip(
                  backgroundColor:
                      _starColor[h.star]!.withValues(alpha: 0.15),
                  avatar: CircleAvatar(
                      backgroundColor: _starColor[h.star], radius: 5),
                  label: Text('${_starLabel[h.star]} ${h.name} '
                      '(${h.power})'),
                ),
            ],
          ),
        ]),
        _card('Dungeon', [
          Text('Next floor: ${_floor + 1} - enemy power ${30 + (_floor + 1) * 18}'),
          const SizedBox(height: 4),
          Text(_strongest == null
              ? 'You need a hero first.'
              : 'Your strongest: ${_strongest!.name} (${_strongest!.power} power)'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _battle,
            icon: const Icon(Icons.sports_kabaddi),
            label: const Text('Battle!'),
          ),
          if (_battleLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _battleLog)
                    Text(line,
                        style: TextStyle(
                            fontSize: 12,
                            color: line.startsWith('VICTORY')
                                ? Colors.green
                                : line.startsWith('Defeated')
                                    ? Colors.red
                                    : null)),
                ],
              ),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16, top: 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
