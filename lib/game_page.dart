import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Hero;
import 'package:flutter/services.dart';

import 'battle_page.dart';
import 'widgets/glow_border.dart';
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
  String _username = 'player';
  String? _avatar;
  List<Hero> _roster = [];
  List<String> _teamIds = [];
  bool _claimed = false;
  bool _busy = false;
  bool _isAdmin = false;
  bool _loaded = false;
  Future<List<LeaderRow>>? _lbFuture;
  final Map<String, int> _domColors = {};

  int _dFloor = 1;
  final _floorCtrl = TextEditingController();

  // heroes tab list state
  String _hSearch = '';
  int _hStar = 0; // 0 = all
  int _hPage = 1;
  static const _hPageSz = 36;

  // team picker sheet state
  String _pSearch = '';
  int _pStar = 0;
  int _pPage = 1;
  static const _pPageSz = 25;

  // admin fields
  final _goldUser = TextEditingController();
  final _goldAmt = TextEditingController();
  int _hStarA = 3;
  final _hName = TextEditingController();
  final _rmName = TextEditingController();
  final _artName = TextEditingController();
  final _artUrl = TextEditingController();
  final _roomKey = TextEditingController();
  final _roomUrl = TextEditingController();
  final _ahAtk = TextEditingController();
  final _ahHp = TextEditingController();
  final _ahDef = TextEditingController();
  final _gcUser = TextEditingController();
  final _gcName = TextEditingController();
  int _gcStar = 6;
  final _csHero = TextEditingController();
  final _csName = TextEditingController();
  final _csAtk = TextEditingController();
  final _csHp = TextEditingController();
  final _csDef = TextEditingController();
  final _csUrl = TextEditingController();
  int _csStar = 0;
  final _gsUser = TextEditingController();
  final _gsHero = TextEditingController();
  final _gsSkin = TextEditingController();
  final _ahUlt = TextEditingController();
  final _suName = TextEditingController();
  final _suUlt = TextEditingController();
  final _skName = TextEditingController();
  final _skVal = TextEditingController();
  String _skKindA = 'damage';

  static const _starColor = {
    1: Colors.grey,
    2: Colors.green,
    3: Colors.blue,
    4: Colors.purple,
    5: Colors.amber,
    6: Color(0xFFE53935),
    7: Color(0xFFFFD700),
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
    _floorCtrl.dispose();
    _goldUser.dispose();
    _goldAmt.dispose();
    _hName.dispose();
    _rmName.dispose();
    _artName.dispose();
    _artUrl.dispose();
    _skName.dispose();
    _skVal.dispose();
    _roomKey.dispose();
    _roomUrl.dispose();
    _ahAtk.dispose();
    _ahHp.dispose();
    _ahDef.dispose();
    _gcUser.dispose();
    _gcName.dispose();
    _csHero.dispose();
    _csName.dispose();
    _csAtk.dispose();
    _csHp.dispose();
    _csDef.dispose();
    _csUrl.dispose();
    _gsUser.dispose();
    _gsHero.dispose();
    _gsSkin.dispose();
    _ahUlt.dispose();
    _suName.dispose();
    _suUlt.dispose();
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

  List<Hero> _filterRoster(String q, int star) {
    final t = q.trim().toLowerCase();
    return _roster.where((h) {
      if (star > 0 && h.star != star) return false;
      if (t.isNotEmpty && !h.name.toLowerCase().contains(t)) return false;
      return true;
    }).toList();
  }

  Future<void> _refresh() async {
    _lbFuture = _game.leaderboard();
    try {
      final coins = await _game.coins();
      final roster = await _game.roster();
      final floor = await _game.floorCleared();
      final streak = await _game.streakDays();
      final claimed = await _game.claimedToday();
      final admin = await _game.isAdmin();
      final team = await _game.loadTeam();
      final uname = await _game.username();
      final av = await _game.avatarUrl();
      if (!mounted) return;
      setState(() {
        _coins = coins;
        _roster = roster;
        _floor = floor;
        _streak = streak;
        _claimed = claimed;
        _isAdmin = admin;
        _username = uname;
        _avatar = av;
        _teamIds = team.where((id) => roster.any((h) => h.id == id)).toList();
        if (_floorCtrl.text.isEmpty) {
          _dFloor = floor + 1;
          _floorCtrl.text = '$_dFloor';
        }
        _loaded = true;
      });
      for (final h in roster) {
        if (h.star == 7 && h.picture != null &&
            !_domColors.containsKey(h.id)) {
          _game.dominantColor(h.picture!).then((v) {
            if (mounted) setState(() => _domColors[h.id] = v);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loaded = true);
        _snack('Sync problem: '
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
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

  Future<void> _changeAvatar() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      await _game.uploadAvatar(bytes);
      _snack('Profile photo updated');
    } catch (e) {
      _snack('Upload failed: ${e.toString().replaceFirst('Exception: ', '')}');
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
                                  fit: BoxFit.contain,
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
            Text(
                'ATK ${h.atk}   HP ${h.hpStat}   DEF ${h.defStat}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E3A8A))),
            const SizedBox(height: 6),
            Text('Level ${h.level} / ${Hero.maxLevel}'
                '${h.bonus > 0 ? " • synthesized +${h.bonus}" : ""}'),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (h.exp / h.expNeed).clamp(0.0, 1.0),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('EXP ${h.exp}/${h.expNeed}',
                  style: const TextStyle(fontSize: 11)),
            ]),
            if (h.ownedSkins.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Skins (${h.ownedSkins.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(h.skin == null
                  ? 'None equipped'
                  : 'Equipped: ${h.skin!.name}'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in h.ownedSkins)
                    if (h.skin?.id != s.id)
                      OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            await _game.equipSkin(h.id, s.id);
                            _snack('Skin equipped: ${s.name}');
                          } catch (e) {
                            _snack(e.toString()
                                .replaceFirst('Exception: ', ''));
                          }
                          _refresh();
                        },
                        child: Text(s.name),
                      ),
                  if (h.skin != null)
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await _game.equipSkin(h.id, null);
                          _snack('Skin removed');
                        } catch (e) {
                          _snack(e.toString()
                              .replaceFirst('Exception: ', ''));
                        }
                        _refresh();
                      },
                      child: const Text('Remove skin'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text('Skill: ${h.skill.name}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(h.skill.desc, style: const TextStyle(fontSize: 13)),
            if (h.ultText != null && h.ultText!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.3)),
                ),
                child: Text(
                  h.ultText!,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
                'Sell value: ${h.sellValue} coins - wins give '
                '${20}+ EXP for free level-ups',
                style: const TextStyle(fontSize: 12)),
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
                    _openSynthesize(i);
                  },
                  icon: const Icon(Icons.science),
                  label: const Text('Synthesize'),
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

  Future<void> _openSynthesize(int targetIdx) async {
    final target = _roster[targetIdx];
    final selected = <int>[];
    var synStar = 0;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, sb) {
            final fodder = [
              for (var i = 0; i < _roster.length; i++)
                if (i != targetIdx && !_roster[i].locked) i
            ];
            final avail = [
              for (final i in fodder)
                if (synStar == 0 || _roster[i].star == synStar) i
            ];
            var gain = 0;
            for (final i in selected) {
              gain += Hero.fodderGain[_roster[i].star] ?? 0;
            }
            var refund = 0;
            for (final i in selected) {
              refund += _roster[i].star * 5;
            }

            void selectAllStar(int s) {
              final cap = 10 - selected.length;
              if (cap <= 0) return;
              var added = 0;
              for (final i in fodder) {
                if (added >= cap) break;
                if (s != 0 && _roster[i].star != s) continue;
                if (!selected.contains(i)) {
                  selected.add(i);
                  added++;
                }
              }
              sb(() {});
            }

            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.88,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(children: [
                    Text('Feed heroes to ${target.name}',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        '${selected.length}/10 picked - +$gain bonus'
                        '${refund > 0 ? ", +$refund coins back" : ""}',
                        style: Theme.of(ctx).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in const [0, 1, 2, 3, 4, 5, 6, 7])
                          FilterChip(
                            label: Text(s == 0
                                ? 'All'
                                : '$s★ (${fodder.where((i) => _roster[i].star == s).length})'),
                            selected: synStar == s,
                            onSelected: (_) async {
                              if (s == 0) {
                                synStar = 0;
                                sb(() {});
                                return;
                              }
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (dctx) => AlertDialog(
                                  title: Text('Use all $s★ heroes?'),
                                  content: const Text(
                                      'Auto-selects every unlocked hero of that star (max 10) as fodder. Locked heroes are never touched.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dctx, false),
                                        child: const Text('Cancel')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dctx, true),
                                        child: const Text('Yes, use them')),
                                  ],
                                ),
                              );
                              if (yes != true) return;
                              selected.clear();
                              for (final i in fodder) {
                                if (selected.length >= 10) break;
                                if (_roster[i].star == s) selected.add(i);
                              }
                              synStar = s;
                              sb(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final s in const [1, 2, 3, 4, 5, 6, 7])
                          OutlinedButton(
                            onPressed: () => selectAllStar(s),
                            child: Text('All $s★',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        if (selected.isNotEmpty)
                          OutlinedButton(
                            onPressed: () {
                              selected.clear();
                              sb(() {});
                            },
                            child: const Text('Clear',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ]),
                ),
                Expanded(
                  child: avail.isEmpty
                      ? const Center(child: Text('No heroes for this filter'))
                      : ListView.builder(
                          itemCount: avail.length,
                          itemBuilder: (ctx, k) {
                            final i = avail[k];
                            final h = _roster[i];
                            final sel = selected.contains(i);
                            return ListTile(
                              dense: true,
                              leading: Text('★${h.star}',
                                  style: TextStyle(
                                      color: _starColor[h.star]!,
                                      fontWeight: FontWeight.bold)),
                              title: Text(h.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  'Lv ${h.level} - +${Hero.fodderGain[h.star]} bonus',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Icon(
                                  sel
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: sel ? Colors.teal : null),
                              onTap: () {
                                sb(() {
                                  if (sel) {
                                    selected.remove(i);
                                  } else if (selected.length < 10) {
                                    selected.add(i);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Max 10 fodder at once')));
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                setState(() => _busy = true);
                                try {
                                  final (nb, cg) = await _game.synthesize(
                                      targetIdx, selected);
                                  _snack(
                                      'Synthesized! +$nb bonus, +$cg coins');
                                } catch (e) {
                                  _snack(e
                                      .toString()
                                      .replaceFirst('Exception: ', ''));
                                } finally {
                                  if (mounted) {
                                    setState(() => _busy = false);
                                  }
                                }
                                _refresh();
                              },
                        child: const Text('Synthesize'),
                      ),
                    ),
                  ]),
                ),
              ]),
            );
          },
        );
      },
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
      _snack('Select your team first');
      return;
    }
    final f = int.tryParse(_floorCtrl.text.trim()) ?? _dFloor;
    if (f < 1) {
      _snack('Floor must be 1 or more');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _game.battle(team, f);
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

  // ---------- shared list controls ----------
  Widget _searchField(String hint, void Function(String) on) {
    return TextField(
      onChanged: on,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _starChips(int cur, void Function(int) on) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ChoiceChip(
            label: const Text('All'),
            selected: cur == 0,
            onSelected: (_) => on(0)),
        for (var s = 1; s <= 7; s++)
          ChoiceChip(
              label: Text('$s★'),
              selected: cur == s,
              onSelected: (_) => on(s)),
      ],
    );
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
      _card('Profile', [
        Row(children: [
          GestureDetector(
            onTap: _busy ? null : _changeAvatar,
            child: Stack(children: [
              GlowBorder(
                color: const Color(0xFF60A5FA),
                radius: 12,
                child: Container(
                  width: 84,
                  height: 84,
                  color: Theme.of(context).colorScheme.surface,
                  child: _avatar != null
                      ? Image.network(_avatar!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.person, size: 40))
                      : const Icon(Icons.person, size: 40),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.camera_alt,
                      size: 13, color: Colors.white),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_username,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Highest dungeon: $_floor',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('Tap the photo to change it',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ]),
      ]),
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
          'Rates: 1★ 34%, 2★ 35%, 3★ 25%, 4★ 5%, 5★ 1%, 6★ 0.5%. '
          '7★ exists but ONLY via admin Give card. No pity - rolls happen '
          'on the server.',
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
    final filtered = _filterRoster(_hSearch, _hStar);
    final hPages =
        filtered.isEmpty ? 1 : (filtered.length + _hPageSz - 1) ~/ _hPageSz;
    final hPage = _hPage.clamp(1, hPages);
    final shown =
        filtered.skip((hPage - 1) * _hPageSz).take(_hPageSz).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _coinsBar(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          _searchField('Search heroes...', (v) {
            _hSearch = v;
            _hPage = 1;
            setState(() {});
          }),
          const SizedBox(height: 8),
          _starChips(_hStar, (s) {
            _hStar = s;
            _hPage = 1;
            setState(() {});
          }),
        ]),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.58,
          ),
          itemCount: shown.length,
          itemBuilder: (ctx, i) {
            final h = shown[i];
            final c = _starColor[h.star]!;
            return InkWell(
              onTap: () => _heroSheet(_roster.indexOf(h)),
              child: GlowBorder(
                color: h.star == 7 && h.picture != null
                    ? Color(_domColors[h.id] ?? 0xFFFFD700)
                    : c,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (h.picture != null)
                        Image.network(h.picture!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _starHeader(h, c))
                      else
                        _starHeader(h, c),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      ),
                      if (h.locked)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: Icon(Icons.lock,
                              size: 14, color: Colors.white),
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
                              Text('★' * h.star,
                                  style: TextStyle(
                                      color: c,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(blurRadius: 6, color: c),
                                      ])),
                              Text(h.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 6,
                                            color: Colors.black),
                                      ])),
                              Text(
                                  'Lv ${h.level} • ${h.power} pw'
                                  '${h.bonus > 0 ? " • +${h.bonus}" : ""}',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 4,
                                            color: Colors.black),
                                      ])),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (hPages > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: hPage > 1
                    ? () => setState(() => _hPage = hPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page $hPage / $hPages'),
              IconButton(
                onPressed: hPage < hPages
                    ? () => setState(() => _hPage = hPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No heroes match.',
              style: Theme.of(context).textTheme.bodySmall),
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

  Future<void> _openTeamPicker() async {
    _pSearch = '';
    _pStar = 0;
    _pPage = 1;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, sb) {
            final filtered = _filterRoster(_pSearch, _pStar);
            final pPages =
                filtered.isEmpty ? 1 : (filtered.length + _pPageSz - 1) ~/ _pPageSz;
            final pPage = _pPage.clamp(1, pPages);
            final shown =
                filtered.skip((pPage - 1) * _pPageSz).take(_pPageSz).toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.85,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(children: [
                    _searchField('Search heroes...', (v) {
                      _pSearch = v;
                      _pPage = 1;
                      sb(() {});
                    }),
                    const SizedBox(height: 8),
                    _starChips(_pStar, (s) {
                      _pStar = s;
                      _pPage = 1;
                      sb(() {});
                    }),
                    const SizedBox(height: 4),
                    Text('${_teamIds.length} / 5 selected',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (ctx, i) {
                      final h = shown[i];
                      final sel = _teamIds.contains(h.id);
                      final order = _teamIds.indexOf(h.id) + 1;
                      return ListTile(
                        dense: true,
                        leading: h.picture != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(h.picture!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        Text('★${h.star}',
                                            style: TextStyle(
                                                color: _starColor[h.star]!,
                                                fontWeight:
                                                    FontWeight.bold))))
                            : Text('★${h.star}',
                                style: TextStyle(
                                    color: _starColor[h.star]!,
                                    fontWeight: FontWeight.bold)),
                        title: Text(h.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            'Lv ${h.level} • ${h.power} pw'
                            '${h.skill.name.isNotEmpty ? " • ${h.skill.name}" : ""}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: sel
                            ? CircleAvatar(
                                radius: 12,
                                child: Text('$order',
                                    style: const TextStyle(fontSize: 11)))
                            : const Icon(Icons.add_circle_outline),
                        onTap: () {
                          _toggleTeam(h.id);
                          sb(() {});
                        },
                      );
                    },
                  ),
                ),
                if (pPages > 1)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: pPage > 1
                              ? () {
                                  _pPage = pPage - 1;
                                  sb(() {});
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page $pPage / $pPages'),
                        IconButton(
                          onPressed: pPage < pPages
                              ? () {
                                  _pPage = pPage + 1;
                                  sb(() {});
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Color _noteBg(String n) => n.startsWith('Synergy')
      ? const Color(0xFF1E3A8A)
      : n.startsWith('Bulwark')
          ? const Color(0xFF0F2A5C)
          : const Color(0xFFB45309);

  IconData _noteIcon(String n) => n.startsWith('Synergy')
      ? Icons.bolt
      : n.startsWith('Bulwark')
          ? Icons.shield
          : Icons.groups;

  String _ord(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  Widget _dungeonTab() {
    final notes = GameService.comboNotes(_team);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _coinsBar(),
      _card('Floor', [
        Text('Highest floor cleared: ${_floor == 0 ? "none" : "$_floor"}'),
        const SizedBox(height: 8),
        TextField(
          controller: _floorCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Floor to fight',
            hintText: 'any floor - even beyond your record',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) =>
              setState(() => _dFloor = int.tryParse(v) ?? _dFloor),
        ),
        const SizedBox(height: 8),
        Text(
          'Floor $_dFloor: ${GameService.waveInfo(_dFloor).$1} monsters, '
          '${GameService.waveInfo(_dFloor).$2} power each'
          '${_dFloor % 5 == 0 ? " + BOSS" : ""} - reward ${40 + _dFloor * 12} coins',
        ),
        const SizedBox(height: 4),
        const Text(
          'Note: your record only advances by clearing your next floor '
          'in order - free input is for experimenting.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('Your team (max 5 - order = attack order)', [
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
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _noteBg(n),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(_noteIcon(n), size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(n,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white))),
                ]),
              ),
            ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _roster.isEmpty ? null : _openTeamPicker,
          icon: const Icon(Icons.group_add),
          label: const Text('Choose heroes'),
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
            'Waves hit random heroes - sustain (Vampiric) and armor '
            '(Bulwark stacks) keep a team of 5 alive.',
            style: TextStyle(fontSize: 12)),
      ]),
      _card('Leaderboard - highest floor', [
        FutureBuilder<List<LeaderRow>>(
          future: _lbFuture,
          builder: (ctx, snap) {
            if (snap.hasError) {
              return const Text('Leaderboard unavailable right now.',
                  style: TextStyle(fontSize: 13));
            }
            if (!snap.hasData) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ));
            }
            final rows = snap.data!;
            if (rows.isEmpty) {
              return const Text('No players yet.');
            }
            return Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: rows[i].username == _username
                            ? const Color(0xFF1E3A8A).withValues(alpha: 0.12)
                            : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: rows[i].username == _username
                            ? Border.all(color: const Color(0xFF1E3A8A))
                            : null,
                      ),
                      child: Row(children: [
                        SizedBox(
                          width: 44,
                          child: Text(_ord(i + 1),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        Expanded(
                          child: Text(rows[i].username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('${rows[i].floor}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color:
                                    Theme.of(ctx).colorScheme.primary)),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
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
          const SizedBox(height: 8),
          const Text(
            'To become admin, run in Supabase SQL editor:\n'
            "update profiles set is_admin = true where username = 'YOUR_USERNAME';\n"
            'then reopen the app.',
            style: TextStyle(fontSize: 12),
          ),
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
              initialValue: _hStarA,
              decoration: const InputDecoration(
                  labelText: 'Star', border: OutlineInputBorder()),
              items: [
                for (var s = 1; s <= 7; s++)
                  DropdownMenuItem(value: s, child: Text('$s★'))
              ],
              onChanged: (v) => setState(() => _hStarA = v ?? 3),
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
                : () {
                    final sn = _skName.text.trim();
                    final sv = double.tryParse(_skVal.text.trim());
                    final a = int.tryParse(_ahAtk.text.trim());
                    final hpv = int.tryParse(_ahHp.text.trim());
                    final dv = int.tryParse(_ahDef.text.trim());
                    _run(
                      () => _game.adminAddHero(
                        _hStarA,
                        _hName.text,
                        skillName: sn.isEmpty ? null : sn,
                        skillKind: sn.isEmpty ? null : _skKindA,
                        skillValue:
                            (sn.isEmpty || sv == null) ? null : sv / 100,
                        atk: a,
                        hp: hpv,
                        def: dv,
                        ultText: _ahUlt.text.trim().isEmpty
                            ? null
                            : _ahUlt.text.trim(),
                      ),
                      'Hero added to pool',
                    );
                  },
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
                labelText: 'Hero name (for remove)',
                border: OutlineInputBorder())),
        const Divider(height: 24),
        Text('Custom skill for new hero (optional)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _skName,
            decoration: const InputDecoration(
                labelText: 'Skill name (empty = random skills)',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _skKindA,
              decoration: const InputDecoration(
                  labelText: 'Effect', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'damage', child: Text('Berserk: +dmg%')),
                DropdownMenuItem(value: 'crit', child: Text('Keen Eye: crit%')),
                DropdownMenuItem(
                    value: 'lifesteal', child: Text('Vampiric: heal%')),
                DropdownMenuItem(
                    value: 'guard', child: Text('Bulwark: -dmg taken%')),
                DropdownMenuItem(
                    value: 'first', child: Text('Ambush: rounds 1-3%')),
              ],
              onChanged: (v) => setState(() => _skKindA = v ?? 'damage'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
                controller: _skVal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Value % (e.g. 30)',
                    border: OutlineInputBorder())),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: _ahUlt,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText:
                    'Ultimate description (optional - shown on the card)',
                hintText: 'E.g. Summons a sacred garden...',
                border: OutlineInputBorder())),
        const Divider(height: 24),
        Text('Custom base stats (optional - all three, absolute values)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _ahAtk,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'ATK', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: _ahHp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'HP', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: _ahDef,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'DEF', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 8),
        const Text('Leave empty = default stats for that star.',
            style: TextStyle(fontSize: 12)),
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
          'Art applies to every card of that hero name. Tip: upload images '
          'to Supabase Storage (public bucket) and paste the public URL.',
          style: TextStyle(fontSize: 12),
        ),
        const Divider(height: 24),
        Text('Set ultimate (existing hero - updates pool AND owned cards)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _suName,
            decoration: const InputDecoration(
                labelText: 'Hero name', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _suUlt,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText: 'Ultimate description',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminSetUlt(_suName.text, _suUlt.text.trim()),
                  'Ultimate saved'),
          child: const Text('Save ultimate'),
        ),
        const Divider(height: 24),
        Text('Set ultimate (existing hero - updates pool AND owned cards)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _suName,
            decoration: const InputDecoration(
                labelText: 'Hero name', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _suUlt,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText: 'Ultimate description',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminSetUlt(_suName.text, _suUlt.text.trim()),
                  'Ultimate saved'),
          child: const Text('Save ultimate'),
        ),
        const Divider(height: 24),
        Text('Set ultimate (existing hero - updates pool AND owned cards)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _suName,
            decoration: const InputDecoration(
                labelText: 'Hero name', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _suUlt,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText: 'Ultimate description',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminSetUlt(_suName.text, _suUlt.text.trim()),
                  'Ultimate saved'),
          child: const Text('Save ultimate'),
        ),
                Text('Set ultimate (existing hero - updates pool AND owned cards)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _suName,
            decoration: const InputDecoration(
                labelText: 'Hero name', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _suUlt,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText: 'Ultimate description',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminSetUlt(_suName.text, _suUlt.text.trim()),
                  'Ultimate saved'),
          child: const Text('Save ultimate'),
        ),
        const Divider(height: 24),
const Divider(height: 24),
        Text('Dungeon room art',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _roomKey,
            decoration: const InputDecoration(
                labelText: 'Room key',
                hintText: 'floor number, or: default / boss',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: _roomUrl,
            decoration: const InputDecoration(
                labelText: 'https://.../room.png',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminSetRoom(
                      _roomKey.text, _roomUrl.text.trim()),
                  'Room art saved'),
          child: const Text('Save room art'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Battle background uses: exact floor -> boss room (floors 5,10..) '
          '-> default room. Set one default + one boss to start.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('Admin - give card (6★/7★ live here)', [
        TextField(
            controller: _gcUser,
            decoration: const InputDecoration(
                labelText: 'Username', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _gcStar,
              decoration: const InputDecoration(
                  labelText: 'Star', border: OutlineInputBorder()),
              items: [
                for (var s = 1; s <= 7; s++)
                  DropdownMenuItem(value: s, child: Text('$s★'))
              ],
              onChanged: (v) => setState(() => _gcStar = v ?? 6),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
                controller: _gcName,
                decoration: const InputDecoration(
                    labelText: 'Hero name', border: OutlineInputBorder())),
          ),
        ]),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminGiveCard(
                      _gcUser.text, _gcStar, _gcName.text),
                  'Card given'),
          child: const Text('Give card'),
        ),
      ]),
      _card('Admin - skins', [
        Text('Create skin', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _csHero,
                decoration: const InputDecoration(
                    labelText: 'Hero name', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: _csName,
                decoration: const InputDecoration(
                    labelText: 'Skin name', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _csStar,
              decoration: const InputDecoration(
                  labelText: 'Rarity override (0=keep)',
                  border: OutlineInputBorder()),
              items: [
                for (var s = 0; s <= 7; s++)
                  DropdownMenuItem(value: s, child: Text(s == 0 ? 'keep' : '$s★'))
              ],
              onChanged: (v) => setState(() => _csStar = v ?? 0),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _csAtk,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '+ATK', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: _csHp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '+HP', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: _csDef,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '+DEF', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: _csUrl,
            decoration: const InputDecoration(
                labelText: 'Skin picture URL (optional)',
                border: OutlineInputBorder())),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminCreateSkin(
                      _csHero.text,
                      _csName.text,
                      _csStar,
                      int.tryParse(_csAtk.text.trim()) ?? 0,
                      int.tryParse(_csHp.text.trim()) ?? 0,
                      int.tryParse(_csDef.text.trim()) ?? 0,
                      _csUrl.text),
                  'Skin created'),
          child: const Text('Create skin'),
        ),
        const Divider(height: 24),
        Text('Grant skin (to every card of that hero the user owns)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
            controller: _gsUser,
            decoration: const InputDecoration(
                labelText: 'Username', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _gsHero,
                decoration: const InputDecoration(
                    labelText: 'Hero name', border: OutlineInputBorder()))),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: _gsSkin,
                decoration: const InputDecoration(
                    labelText: 'Skin name', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => _game.adminGrantSkin(
                      _gsUser.text, _gsHero.text, _gsSkin.text),
                  'Skin granted'),
          child: const Text('Grant skin'),
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
