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
  List<String> _teamIds = [];
  bool _claimed = false;
  bool _busy = false;
  bool _isAdmin = false;
  bool _loaded = false;

  int _dFloor = 1;

  // admin fields
  final _goldUser = TextEditingController();
  final _goldAmt = TextEditingController();
  int _hStar = 3;
  final _hName = TextEditingController();
  final _rmName = TextEditingController();
  final _artName = TextEditingController();
  final _artUrl = TextEditingController();

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
    _tabs = TabController(length: 5, vsync: this);
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

  List<Hero> get _team {
    final out = <Hero>[];
    for (final id in _teamIds) {
      for (final h in _roster) {
        if (h.id == id) {
          out.add(h);
          break;
        }
      }
    }
    return out;
  }

  Future<void> _refresh() async {
    try {
      final coins = await _game.coins();
      final roster = await _game.roster();
      final floor = await _game.floorCleared();
      final streak = await _game.streakDays();
      final claimed = await _game.claimedToday();
      final admin = await _game.isAdmin();
      final team = await _game.loadTeam();
      if (!mounted) return;
      setState(() {
        _coins = coins;
        _roster = roster;
        _floor = floor;
        _streak = streak;
        _claimed = claimed;
        _isAdmin = admin;
        _teamIds =
            team.where((id) => roster.any((h) => h.id == id)).toList();
        if (_dFloor > floor + 1) _dFloor = floor + 1;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
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
            height: count == 100 ? 420 : (count == 10 ? 300 : 170),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count == 1 ? 1 : 5,
                childAspectRatio: 0.62,
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
                    padding: const EdgeInsets.all(3),
                    child: Column(
                      children: [
                        Expanded(
                          child: r.hero.picture != null
                              ? Image.network(r.hero.picture!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, _, _) => Center(
                                      child: Text('★' * r.hero.star,
                                          style: TextStyle(
                                              color: c,
                                              fontWeight:
                                                  FontWeight.bold))))
                              : Center(
                                  child: Text('★' * r.hero.star,
                                      style: TextStyle(
                                          color: c,
                                          fontWeight: FontWeight.bold))),
                        ),
                        Text(r.hero.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9)),
                        Text('${r.hero.power} pw',
                            style: const TextStyle(fontSize: 8)),
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
              if (h.picture != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(h.picture!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 56)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('★' * h.star,
                        style: TextStyle(
                            color: _starColor[h.star],
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    Text('${h.name}${h.locked ? '  🔒' : ''}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text('Level ${h.level} / ${Hero.maxLevel} - Power ${h.power}'),
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

  void _toggleTeam(String id) async {
    setState(() {
      if (_teamIds.contains(id)) {
        _teamIds.remove(id);
      } else if (_teamIds.length < 5) {
        _teamIds.add(id);
      } else {
        _snack('Team is full (max 5)');
      }
    });
    await _game.saveTeam(_teamIds);
  }

  Future<void> _battle() async {
    final team = _team;
    if (team.isEmpty) {
      _snack('Select your team first (tap heroes below)');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _game.battle(team, _dFloor);
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

  // ---------- admin actions ----------
  Future<void> _run(Future<void> Function() f, String okMsg) async {
    setState(() => _busy = true);
    try {
      await f();
      _snack(okMsg);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Material(
          color: cs.surfaceContainerHighest,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Daily'),
              Tab(text: 'Gacha'),
              Tab(text: 'Heroes'),
              Tab(text: 'Dungeon'),
              Tab(text: 'Admin'),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tabs.index,
            children: [
              _daily(),
              _gachaTab(),
              _heroesTab(),
              _dungeonTab(),
              _adminTab(),
            ],
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
          'Rates: 1★ 34%, 2★ 35%, 3★ 25%, 4★ 5%, 5★ 1%. No pity - every roll '
          'happens on the server.',
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
            childAspectRatio: 0.62,
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
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(
                      child: h.picture != null
                          ? Image.network(h.picture!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, _, _) => _starHeader(h, c))
                          : _starHeader(h, c),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        children: [
                          Text(h.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          Text('Lv ${h.level} • ${h.power} pw',
                              style: const TextStyle(fontSize: 9)),
                          if (h.locked)
                            const Icon(Icons.lock,
                                size: 11, color: Colors.grey),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _starHeader(Hero h, Color c) {
    return Container(
      color: c.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text('★' * h.star,
          style: TextStyle(
              color: c, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _dungeonTab() {
    final maxFloor = _floor + 1;
    final (cnt, pw) = GameService.waveInfo(_dFloor);
    final notes = GameService.comboNotes(_team);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _coinsBar(),
      _card('Dungeon', [
        Text('Highest floor cleared: ${_floor == 0 ? "none" : "$_floor"}'),
        const SizedBox(height: 8),
        Slider(
          value: _dFloor.clamp(1, maxFloor).toDouble(),
          min: 1,
          max: maxFloor.toDouble(),
          divisions: maxFloor - 1 > 0 ? maxFloor - 1 : 1,
          label: '$_dFloor',
          onChanged: (v) => setState(() => _dFloor = v.round()),
        ),
        Text('Floor $_dFloor: $cnt monsters, $pw power each'
            '${_dFloor % 5 == 0 ? " + BOSS" : ""}'
            ' - reward ${40 + _dFloor * 12} coins'),
      ]),
      _card('Your team (max 5 - tap to add, order = attack order)', [
        if (_team.isEmpty)
          const Text('No heroes selected yet.'),
        if (_team.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _team.length; i++)
                Chip(
                  avatar: CircleAvatar(
                      backgroundColor: _starColor[_team[i].star], radius: 5),
                  label: Text('${i + 1}. ${_team[i].name}'),
                  onDeleted: () => _toggleTeam(_team[i].id),
                ),
            ],
          ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.bolt, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(n, style: const TextStyle(fontSize: 12))),
              ]),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final h in _roster)
              FilterChip(
                label: Text('${h.name} ★${h.star}'),
                selected: _teamIds.contains(h.id),
                onSelected: (_) => _toggleTeam(h.id),
              ),
          ],
        ),
      ]),
      _card('Battle', [
        FilledButton.icon(
          onPressed: _busy ? null : _battle,
          icon: const Icon(Icons.sports_kabaddi),
          label: const Text('Battle!'),
        ),
        const SizedBox(height: 8),
        const Text(
            'Watch the fight - speed it up or skip. Enemy waves hit random '
            'heroes, so keep the team alive with Vampiric/Bulwark.',
            style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }

  Widget _adminTab() {
    if (!_isAdmin) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _card('Admin', [
          const Row(children: [
            Icon(Icons.lock, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Admin only. Your account is not an admin.')),
          ]),
        ]),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card('Admin - give gold', [
        TextField(
            controller: _goldUser,
            decoration: const InputDecoration(
                labelText: 'Username', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _goldAmt,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Amount (negative to take)',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminGiveGold(_goldUser.text.trim(),
                      int.tryParse(_goldAmt.text.trim()) ?? 0),
                  'Gold updated'),
          child: const Text('Give gold'),
        ),
      ]),
      _card('Admin - heroes & art', [
        Text('Add hero to gacha pool',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _hStar,
              decoration: const InputDecoration(
                  labelText: 'Star', border: OutlineInputBorder()),
              items: [for (var s = 1; s <= 5; s++) DropdownMenuItem(value: s, child: Text('$s★'))],
              onChanged: (v) => setState(() => _hStar = v ?? 3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
                controller: _hName,
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder())),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => _game.adminAddHero(_hStar, _hName.text),
                    'Hero added to pool'),
            child: const Text('Add hero'),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => _game.adminRemoveHero(_rmName.text), 'Hero removed'),
            child: const Text('Remove hero'),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: _rmName,
            decoration: const InputDecoration(
                labelText: 'Hero name (for remove)', border: OutlineInputBorder())),
        const Divider(height: 24),
        Text('Set hero art (picture URL)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _artName,
            decoration: const InputDecoration(
                labelText: 'Hero name', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _artUrl,
            decoration: const InputDecoration(
                labelText: 'https://.../hero.png',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminSetArt(_artName.text, _artUrl.text.trim()),
                  'Art saved'),
          child: const Text('Save art'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Art applies to every card of that hero name - gacha, roster and '
          'battle. Tip: upload images to Supabase Storage (public bucket) '
          'and paste the public URL.',
          style: TextStyle(fontSize: 12),
        ),
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
