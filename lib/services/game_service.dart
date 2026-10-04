import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class Hero {
  Hero({required this.name, required this.star, required this.power});

  final String name;
  final int star; // 1..5
  final int power;

  Map<String, dynamic> toJson() =>
      {'name': name, 'star': star, 'power': power};

  static Hero fromJson(Map<String, dynamic> j) => Hero(
        name: j['name'] as String,
        star: j['star'] as int,
        power: j['power'] as int,
      );
}

class PullResult {
  PullResult({required this.hero, required this.isDupe, required this.refund});

  final Hero hero;
  final bool isDupe;
  final int refund; // coins returned if dupe
}

class BattleResult {
  BattleResult({required this.win, required this.log, required this.coins});

  final bool win;
  final List<String> log;
  final int coins;
}

class GameService {
  static const _kCoins = 'g_coins';
  static const _kHeroes = 'g_heroes';
  static const _kLast = 'g_last_claim';
  static const _kStreak = 'g_streak';
  static const _kFloor = 'g_floor'; // highest cleared

  static const pullCost = 450;
  static const pull10Cost = 3000;

  static const _names = {
    1: ['Slime', 'Goblin', 'Bandit', 'Farm Boy'],
    2: ['Archer', 'Swordsman', 'Shieldbearer', 'Monk'],
    3: ['Flame Mage', 'Frost Knight', 'Shadow Blade', 'Storm Priest'],
    4: ['Dragon Slayer', 'Void Assassin', 'Celestial Guard', 'Storm Empress'],
    5: ['Sun God Kael', 'Moon Empress Luna', 'Abyss King Varog', 'Starfall Seraph'],
  };
  static const _basePower = {1: 50, 2: 95, 3: 170, 4: 300, 5: 520};
  static const _weights = {1: 40, 2: 30, 3: 20, 4: 8, 5: 2};

  final _rng = Random();

  // ---------- state ----------
  Future<int> coins() async =>
      (await SharedPreferences.getInstance()).getInt(_kCoins) ?? 300;

  Future<int> floor() async =>
      (await SharedPreferences.getInstance()).getInt(_kFloor) ?? 0;

  Future<int> streakDays() async {
    final p = await SharedPreferences.getInstance();
    final today = _today();
    if ((p.getString(_kLast) ?? '') == today) {
      return p.getInt(_kStreak) ?? 0;
    }
    return p.getInt(_kStreak) ?? 0;
  }

  Future<List<Hero>> roster() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kHeroes);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Hero.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _save(int coins, List<Hero> heroes) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCoins, coins);
    await p.setString(
        _kHeroes, jsonEncode(heroes.map((h) => h.toJson()).toList()));
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ---------- daily ----------
  /// Returns coins granted, or -1 if already claimed today.
  Future<int> claimDaily() async {
    final p = await SharedPreferences.getInstance();
    final today = _today();
    if ((p.getString(_kLast) ?? '') == today) return -1;
    var streak = p.getInt(_kStreak) ?? 0;
    // consecutive if last claim was exactly one day ago
    final last = p.getString(_kLast) ?? '';
    final yd = DateTime.now().subtract(const Duration(days: 1));
    final yStr =
        '${yd.year}-${yd.month.toString().padLeft(2, '0')}-${yd.day.toString().padLeft(2, '0')}';
    streak = (last == yStr) ? streak + 1 : 1;
    var bonus = (streak - 1) * 50;
    if (bonus > 300) bonus = 300;
    final reward = 200 + bonus;
    await p.setString(_kLast, today);
    await p.setInt(_kStreak, streak);
    final c = await coins();
    await _save(c + reward, await roster());
    return reward;
  }

  // ---------- gacha ----------
  int _rollStar() {
    final total = _weights.values.reduce((a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in _weights.entries) {
      if (r < e.value) return e.key;
      r -= e.value;
    }
    return 1;
  }

  Hero _makeHero(int star) {
    final pool = _names[star]!;
    final name = pool[_rng.nextInt(pool.length)];
    final p = _basePower[star]!;
    return Hero(
        name: name, star: star, power: (p * (0.9 + _rng.nextDouble() * 0.2)).round());
  }

  Future<List<PullResult>> pull(int count, {bool guarantee3 = false}) async {
    final c = await coins();
    final cost = count == 10 ? pull10Cost : pullCost * count;
    if (c < cost) throw Exception('Not enough coins ($cost needed)');
    final rosterNow = await roster();
    final results = <PullResult>[];
    var best = 0;
    for (var i = 0; i < count; i++) {
      var star = _rollStar();
      if (guarantee3 && i == count - 1 && best < 3) star = 3;
      if (star > best) best = star;
      final h = _makeHero(star);
      final dupe = rosterNow.any((x) => x.name == h.name && x.star == h.star);
      final refund = dupe ? h.star * 30 : 0;
      results.add(PullResult(hero: h, isDupe: dupe, refund: refund));
      if (!dupe) rosterNow.add(h);
    }
    var newCoins = c - cost;
    for (final r in results) {
      newCoins += r.refund;
    }
    await _save(newCoins, rosterNow);
    return results;
  }

  // ---------- dungeon ----------
  static String _enemyName(int floor) {
    const names = [
      'Cave Bat', 'Skeleton', 'Orc Brute', 'Dark Mage',
      'Stone Golem', 'Wraith', 'Chaos Knight', 'Demon Lord'
    ];
    return names[(floor - 1) % names.length];
  }

  Future<BattleResult> battle(Hero hero) async {
    final currentFloor = await floor();
    final f = currentFloor + 1;
    final ePower = 30 + f * 18;
    var pHp = hero.power * 10;
    var eHp = ePower * 8;
    final log = <String>[
      'Floor $f: ${hero.name} (${hero.star}*, ${hero.power} power) '
          'vs ${_enemyName(f)} ($ePower power)'
    ];
    var round = 1;
    while (pHp > 0 && eHp > 0 && round <= 30) {
      final pDmg = (hero.power * (0.85 + _rng.nextDouble() * 0.3)).round();
      eHp -= pDmg;
      log.add('R$round: you hit for $pDmg - enemy $eHp HP');
      if (eHp <= 0) break;
      final eDmg = (ePower * (0.85 + _rng.nextDouble() * 0.3)).round();
      pHp -= eDmg;
      log.add('R$round: enemy hits for $eDmg - you ${pHp > 0 ? pHp : 0} HP');
      round++;
    }
    final win = eHp <= 0;
    final reward = win ? 80 + f * 15 : 10;
    final p = await SharedPreferences.getInstance();
    final c = await coins();
    if (win) {
      await p.setInt(_kFloor, f);
    }
    await _save(c + reward, await roster());
    log.add(win
        ? 'VICTORY! +$reward coins - floor $f cleared'
        : 'Defeated... +$reward coins consolation. Level up heroes and retry.');
    return BattleResult(win: win, log: log, coins: reward);
  }
}
