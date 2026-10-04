import 'package:flutter/material.dart' hide Hero;

import 'battle_page.dart';
import 'services/game_service.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin {
  final _game = GameService();
  late final TabController _tabs;

  int _coins = 0;
  int _streak = 0;
  int _floor = 0;
  List<Hero> _roster = [];
  bool _claimed = false;
  bool _busy = false;

  int _dHeroIdx = 0;
  int _dFloor = 1;

  static const _starColor = {
    1: Colors.grey,
    2: Colors.green,
    3: Colors.blue,
    4: Colors.purple,
    5: Colors.amber,
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final coins = await _game.coins();
    final roster = await _game.roster();
    final floor = await _game.floorCleared();
    final streak = await _game.streakDays();
    final claimed = await _game.claimedToday();
    if (!mounted) return;
    setState(() {
      _coins = coins;
      _roster = roster;
      _floor = floor;
      _streak = streak;
      _claimed = claimed;
      if (_dHeroIdx >= roster.length) _dHeroIdx = 0;
      _dFloor = floor + 1;
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      final r = await _game.claimDaily();
      _snack(r == -1 ? 'Already claimed today' : '+$r coins!');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _refresh();
  }

  Future<void> _gacha(int count) async {
    setState(() => _busy = true);
    try {
      final results = await _game.pull(count);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${count}x Pull!'),
          content: SizedBox(
            width: double.maxFinite,
            height: count == 100 ? 420 : (count == 10 ? 260 : 150),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count == 1 ? 1 : 5,
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
                        Text('★' * r.hero.star,
                            style: TextStyle(
                                color: c, fontWeight: FontWeight.bold)),
                        Text(r.hero.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10)),
                        Text('${r.hero.power} pw',
                            style: const TextStyle(fontSize: 9)),
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
                child: const Text('Nice')),
          ],
        ),
      );
      _refresh();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _heroSheet(int i) async {
    final h = _roster[i];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('★' * h.star,
                  style: TextStyle(
                      color: _starColor[h.star],
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${h.name}${h.locked ? '  🔒' : ''}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 12),
            Text('Level ${h.level} / ${Hero.maxLevel}'),
            Text('Power: ${h.power}'),
            const SizedBox(height: 8),
            Text('Skill: ${h.skill.name}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(h.skill.desc, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text('Sell value: ${h.sellValue} coins',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await _game.levelUp(i);
                      _snack('Level up! Now ${h.level + 1}');
                    } catch (e) {
                      _snack(e.toString().replaceFirst('Exception: ', ''));
                    }
                    _refresh();
                  },
                  icon: const Icon(Icons.trending_up),
                  label:
                      Text('Level up (${GameService.levelCost(h.level)})'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await _game.toggleLock(i);
                      _snack(h.locked ? 'Unlocked' : 'Locked');
                    } catch (e) {
                      _snack(e.toString().replaceFirst('Exception: ', ''));
                    }
                    _refresh();
                  },
                  icon: Icon(h.locked ? Icons.lock_open : Icons.lock),
                  label: Text(h.locked ? 'Unlock' : 'Lock'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final c = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Gift card'),
                        content: TextField(
                          controller: c,
                          decoration: const InputDecoration(
                            hintText: 'recipient username',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('Send')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await _game.gift(i, c.text.trim());
                      _snack('Card gifted!');
                    } catch (e) {
                      _snack(e.toString().replaceFirst('Exception: ', ''));
                    }
                    _refresh();
                  },
                  icon: const Icon(Icons.card_giftcard),
                  label: const Text('Gift'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Sell hero?'),
                        content: Text(
                            'Sell ${h.name} for ${h.sellValue} coins? This cannot be undone.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('Sell')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      final v = await _game.sell(i);
                      _snack('Sold for $v coins');
                    } catch (e) {
                      _snack(e.toString().replaceFirst('Exception: ', ''));
                    }
                    _refresh();
                  },
                  icon: const Icon(Icons.sell),
                  label: Text('Sell (${h.sellValue})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _battle() async {
    if (_roster.isEmpty) {
      _snack('Pull some heroes first!');
      return;
    }
    setState(() => _busy = true);
    try {
      final hero = _roster[_dHeroIdx < _roster.length ? _dHeroIdx : 0];
      final result = await _game.battle(hero, _dFloor);
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => BattlePage(result: result)));
      _refresh();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: cs.surfaceContainerHighest,
          child: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Daily'),
              Tab(text: 'Gacha'),
              Tab(text: 'Heroes'),
              Tab(text: 'Dungeon'),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tabs.index,
            children: [_daily(), _gachaTab(), _heroesTab(), _dungeonTab()],
          ),
        ),
      ],
    );
  }

  Widget _daily() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _coinsBar(),
      _card('Daily reward', [
        Text(_claimed
            ? 'Claimed today. Streak: $_streak day(s). Come back tomorrow!'
            : 'Claim 150 coins + streak bonus (+25/day, up to +175).'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _claim,
          icon: const Icon(Icons.redeem),
          label: Text(_claimed ? 'Claimed' : 'Claim daily reward'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await _game.signOut();
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ]),
    ]);
  }

  Widget _gachaTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _coinsBar(),
      _card('Summon heroes', [
        const Text(
          'Rates: 1★ 34%, 2★ 35%, 3★ 25%, 4★ 5%, 5★ 1%. No pity, no '
          'guarantees - every roll happens on the server.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
                onPressed: _busy ? null : () => _gacha(1),
                child: const Text('1x - 30')),
            OutlinedButton(
                onPressed: _busy ? null : () => _gacha(10),
                child: const Text('10x - 300')),
            FilledButton(
                onPressed: _busy ? null : () => _gacha(100),
                child: const Text('100x - 3000')),
          ],
        ),
      ]),
    ]);
  }

  Widget _heroesTab() {
    if (_roster.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _coinsBar(),
        _card('Heroes (0)', [const Text('No heroes yet - go pull!')]),
      ]);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _coinsBar(),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.72,
          ),
          itemCount: _roster.length,
          itemBuilder: (ctx, i) {
            final h = _roster[i];
            final c = _starColor[h.star]!;
            return InkWell(
              onTap: () => _heroSheet(i),
              child: Card(
                color: c.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: c, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('★' * h.star,
                          style: TextStyle(
                              color: c,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      Text(h.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('Lv ${h.level} • ${h.power} pw',
                          style: const TextStyle(fontSize: 10)),
                      if (h.locked)
                        const Icon(Icons.lock,
                            size: 12, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _dungeonTab() {
    final maxFloor = _floor + 1;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _coinsBar(),
      _card('Dungeon', [
        Text('Highest floor cleared: ${_floor == 0 ? "none" : "$_floor"}'),
        const SizedBox(height: 8),
        Text('Choose floor', style: Theme.of(context).textTheme.labelLarge),
        if (maxFloor > 1)
          Slider(
            value: _dFloor.clamp(1, maxFloor).toDouble(),
            min: 1,
            max: maxFloor.toDouble(),
            divisions: maxFloor - 1,
            label: '$_dFloor',
            onChanged: (v) => setState(() => _dFloor = v.round()),
          )
        else
          const Text('Floor 1 (clear it to unlock deeper floors)'),
        Text(
            'Floor $_dFloor: ${GameService.enemyName(_dFloor)} - '
            'power ${25 + _dFloor * 15} - reward ${40 + _dFloor * 12} coins'),
        const SizedBox(height: 12),
        if (_roster.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<int>(
              value: _dHeroIdx < _roster.length ? _dHeroIdx : 0,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (var i = 0; i < _roster.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                        '★${_roster[i].star} ${_roster[i].name} '
                        '(Lv${_roster[i].level}, ${_roster[i].power})',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _dHeroIdx = v ?? 0),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _battle,
          icon: const Icon(Icons.sports_kabaddi),
          label: const Text('Battle!'),
        ),
        const SizedBox(height: 8),
        const Text('Watch the fight play out - or crank the speed / skip.',
            style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }

  Widget _coinsBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.monetization_on, color: Colors.amber),
              const SizedBox(width: 6),
              Text('$_coins coins',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ]),
            Text('Streak: $_streak'),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
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
