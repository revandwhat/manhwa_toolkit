import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

class Skill {
  Skill({required this.name, required this.kind, required this.value});

  final String name;
  final String kind; // damage | crit | lifesteal | guard | first
  final double value;

  static String descFor(String kind, double value) {
    final p = (value * 100).round();
    switch (kind) {
      case 'damage':
        return '+$p% damage';
      case 'crit':
        return '$p% chance to crit for x1.8';
      case 'lifesteal':
        return 'heals $p% of damage dealt';
      case 'guard':
        return 'takes $p% less damage';
      case 'first':
        return '+$p% damage in rounds 1-3';
    }
    return '';
  }

  String get desc => descFor(kind, value);
}

class Hero {
  Hero({
    required this.id,
    required this.name,
    required this.star,
    this.level = 1,
    required this.skill,
    this.locked = false,
  });

  final String id;
  final String name;
  final int star;
  final int level;
  final Skill skill;
  final bool locked;

  static const maxLevel = 30;
  static const _basePower = {1: 40, 2: 80, 3: 150, 4: 260, 5: 450};

  int get power => (_basePower[star]! * (1 + 0.07 * (level - 1))).round();
  int get sellValue => star * 20 + (level - 1) * 8;

  factory Hero.fromRow(Map<String, dynamic> j) => Hero(
        id: j['id'] as String,
        name: j['name'] as String,
        star: (j['star'] as num).toInt(),
        level: (j['level'] as num?)?.toInt() ?? 1,
        skill: Skill(
          name: (j['skill_name'] ?? '') as String,
          kind: (j['skill_kind'] ?? '') as String,
          value: ((j['skill_value'] ?? 0) as num).toDouble(),
        ),
        locked: (j['locked'] as bool?) ?? false,
      );
}

class PullResult {
  PullResult({required this.hero});

  final Hero hero;
}

class RoundEvent {
  RoundEvent({
    required this.round,
    required this.heroDmg,
    required this.enemyDmg,
    required this.heroHp,
    required this.enemyHp,
    this.crit = false,
    this.heal = 0,
  });

  final int round;
  final int heroDmg;
  final int enemyDmg;
  final int heroHp;
  final int enemyHp;
  final int heal;
  final bool crit;
}

class BattleResult {
  BattleResult({
    required this.win,
    required this.coins,
    required this.floor,
    required this.enemyName,
    required this.enemyPower,
    required this.heroName,
    required this.heroPower,
    required this.events,
  });

  final bool win;
  final int coins;
  final int floor;
  final int enemyPower;
  final int heroPower;
  final String enemyName;
  final String heroName;
  final List<RoundEvent> events;
}

class GameService {
  static const pullCost = 30;
  static const pull10Cost = 300;
  static const pull100Cost = 3000;

  static int levelCost(int level) => 15 + level * 10;

  static String enemyName(int floor) {
    const names = [
      'Cave Bat', 'Skeleton', 'Orc Brute', 'Dark Mage',
      'Stone Golem', 'Wraith', 'Chaos Knight', 'Demon Lord',
    ];
    return names[(floor - 1) % names.length];
  }

  SupabaseClient get _sb => Supabase.instance.client;

  final _rng = Random();
  Map<String, dynamic>? _pcache;
  DateTime? _pcacheAt;

  String _uid() {
    final u = _sb.auth.currentUser;
    if (u == null) throw Exception('Not signed in');
    return u.id;
  }

  void _bust() {
    _pcache = null;
  }

  Future<Map<String, dynamic>> _profile() async {
    if (_pcache != null &&
        _pcacheAt != null &&
        DateTime.now().difference(_pcacheAt!) < const Duration(seconds: 3)) {
      return _pcache!;
    }
    final row = await _sb.from('profiles').select().eq('id', _uid()).single();
    _pcache = row;
    _pcacheAt = DateTime.now();
    return row;
  }

  Future<int> coins() async => ((await _profile())['coins'] ?? 0) as int;

  Future<int> floorCleared() async =>
      ((await _profile())['highest_floor'] ?? 0) as int;

  Future<int> streakDays() async =>
      ((await _profile())['streak'] ?? 0) as int;

  Future<bool> claimedToday() async =>
      ((await _profile())['last_claim'] ?? '') == _today();

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<List<Hero>> roster() async {
    final rows = await _sb
        .from('cards')
        .select()
        .eq('owner', _uid())
        .order('created_at');
    return rows.map((e) => Hero.fromRow(e)).toList();
  }

  Future<int> claimDaily() async {
    final r = await _sb.rpc('claim_daily');
    _bust();
    return (r as num).toInt();
  }

  Future<List<PullResult>> pull(int count) async {
    final rows = await _sb.rpc('gacha_pull', params: {'n': count});
    _bust();
    return (rows as List)
        .map((e) => PullResult(hero: Hero.fromRow(e as Map<String, dynamic>)))
        .toList();
  }

  Future<void> levelUp(int index) async {
    final roster = await this.roster();
    if (index >= roster.length) throw Exception('Card not found');
    await _sb.rpc('level_up_card', params: {'card_id': roster[index].id});
    _bust();
  }

  Future<void> toggleLock(int index) async {
    final roster = await this.roster();
    if (index >= roster.length) throw Exception('Card not found');
    await _sb.rpc('lock_card',
        params: {'card_id': roster[index].id, 'locked': !roster[index].locked});
  }

  Future<int> sell(int index) async {
    final roster = await this.roster();
    if (index >= roster.length) throw Exception('Card not found');
    final r = await _sb.rpc('sell_card', params: {'card_id': roster[index].id});
    _bust();
    return (r as num).toInt();
  }

  Future<void> gift(int index, String username) async {
    final roster = await this.roster();
    if (index >= roster.length) throw Exception('Card not found');
    await _sb.rpc('gift_card',
        params: {'card_id': roster[index].id, 'to_username': username});
  }

  Future<void> signOut() => _sb.auth.signOut();

  /// Battle is simulated locally (so the animation works), but the reward
  /// and floor progression are computed and stored by the server.
  Future<BattleResult> battle(Hero hero, int requestedFloor) async {
    final cleared = await floorCleared();
    final f = requestedFloor.clamp(1, cleared + 1);
    final ePower = 25 + f * 15;
    final pMax = hero.power * 10;
    final eMax = ePower * 8;
    var pHp = pMax;
    var eHp = eMax;
    final events = <RoundEvent>[];
    var round = 1;
    while (pHp > 0 && eHp > 0 && round <= 40) {
      var dmg = hero.power * (0.85 + _rng.nextDouble() * 0.3);
      var crit = false;
      switch (hero.skill.kind) {
        case 'damage':
          dmg *= 1 + hero.skill.value;
        case 'first':
          if (round <= 3) dmg *= 1 + hero.skill.value;
        case 'crit':
          if (_rng.nextDouble() < hero.skill.value) {
            dmg *= 1.8;
            crit = true;
          }
      }
      final hd = dmg.round();
      eHp -= hd;
      var heal = 0;
      if (hero.skill.kind == 'lifesteal') {
        heal = (hd * hero.skill.value).round();
      }
      pHp += heal;
      if (pHp > pMax) pHp = pMax;
      var ed = ePower * (0.85 + _rng.nextDouble() * 0.3);
      if (hero.skill.kind == 'guard') ed *= 1 - hero.skill.value;
      final edd = ed.round();
      pHp -= edd;
      events.add(RoundEvent(
        round: round,
        heroDmg: hd,
        enemyDmg: edd,
        heroHp: pHp > 0 ? pHp : 0,
        enemyHp: eHp > 0 ? eHp : 0,
        crit: crit,
        heal: heal,
      ));
      round++;
    }
    final win = eHp <= 0;
    final coins =
        await _sb.rpc('battle_result', params: {'f': f, 'won': win});
    _bust();
    return BattleResult(
      win: win,
      coins: (coins as num).toInt(),
      floor: f,
      enemyName: enemyName(f),
      enemyPower: ePower,
      heroName: hero.name,
      heroPower: hero.power,
      events: events,
    );
  }
}
