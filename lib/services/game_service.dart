import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Skill {
  Skill({required this.name, required this.kind, required this.value});

  final String name;
  final String kind; // damage | crit | lifesteal | guard | first
  final double value;

  static String label(String kind) => switch (kind) {
        'damage' => 'Berserk',
        'crit' => 'Keen Eye',
        'lifesteal' => 'Vampiric',
        'guard' => 'Bulwark',
        'first' => 'Ambush',
        _ => kind,
      };

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
    this.picture,
  });

  final String id;
  final String name;
  final int star;
  final int level;
  final Skill skill;
  final bool locked;
  final String? picture;

  static const maxLevel = 30;
  static const _basePower = {1: 40, 2: 80, 3: 150, 4: 260, 5: 450};

  int get power => (_basePower[star]! * (1 + 0.07 * (level - 1))).round();
  int get sellValue => star * 20 + (level - 1) * 8;

  factory Hero.fromRow(Map<String, dynamic> j, {Map<String, String>? art}) =>
      Hero(
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
        picture: art?[j['name'] as String],
      );
}

class PullResult {
  PullResult({required this.hero});
  final Hero hero;
}

class FighterInfo {
  const FighterInfo({
    required this.id,
    required this.name,
    required this.power,
    this.star = 0,
    this.picture,
  });

  final String id;
  final String name;
  final int power;
  final int star;
  final String? picture;
}

class HitEvent {
  const HitEvent({
    required this.attackerId,
    required this.targetId,
    required this.attackerName,
    required this.targetName,
    required this.dmg,
    required this.crit,
    required this.heal,
    required this.ko,
    required this.targetHpAfter,
  });

  final String attackerId;
  final String targetId;
  final String attackerName;
  final String targetName;
  final int dmg;
  final bool crit;
  final int heal;
  final bool ko;
  final int targetHpAfter;
}

class RoundEvent {
  const RoundEvent({required this.round, required this.hits});
  final int round;
  final List<HitEvent> hits;
}

class BattleResult {
  const BattleResult({
    required this.win,
    required this.coins,
    required this.floor,
    required this.heroes,
    required this.enemies,
    required this.events,
    required this.comboNotes,
  });

  final bool win;
  final int coins;
  final int floor;
  final List<FighterInfo> heroes;
  final List<FighterInfo> enemies;
  final List<RoundEvent> events;
  final List<String> comboNotes;
}

Uint8List _toPng(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) throw Exception('Bad image');
  final small = img.copyResize(im, width: 256);
  return Uint8List.fromList(img.encodePng(small));
}

class GameService {
  static const pullCost = 30;
  static const pull10Cost = 300;
  static const pull100Cost = 3000;
  static int levelCost(int level) => 15 + level * 10;

  static (int, int) waveInfo(int floor) {
    final count = floor >= 15 ? 8 : (floor >= 10 ? 7 : (floor >= 5 ? 6 : 5));
    final power = 8 + floor * 5;
    return (count, power);
  }

  static String _enemyAt(int floor, int i, int count) {
    const t0 = ['Cave Bat', 'Giant Rat', 'Skeleton', 'Zombie'];
    const t1 = ['Orc Brute', 'Goblin Archer', 'Dark Mage', 'Werewolf'];
    const t2 = ['Stone Golem', 'Wraith', 'Chaos Knight', 'Vampire Lord'];
    const t3 = ['Demon Lord', 'Elder Lich', 'Abyss Wyrm', 'Void Reaper'];
    const boss = ['The Unmaker'];
    final tier = floor >= 15 ? 3 : (floor >= 10 ? 2 : (floor >= 5 ? 1 : 0));
    final pool = [t0, t1, t2, t3][tier];
    if (floor % 5 == 0 && i == count - 1) {
      return (floor >= 15 ? boss : [t1, t2, t3][tier])[0];
    }
    final base = pool[i % pool.length];
    return i >= pool.length ? '$base ${i ~/ pool.length + 1}' : base;
  }

  static List<String> comboNotes(List<Hero> team) {
    final notes = <String>[];
    if (team.isEmpty) return notes;
    final kinds = <String, int>{};
    for (final h in team) {
      kinds[h.skill.kind] = (kinds[h.skill.kind] ?? 0) + 1;
    }
    for (final e in kinds.entries) {
      if (e.value >= 2) {
        notes.add(
            'Synergy: ${e.value}x ${Skill.label(e.key)} -> +20% effect each');
      }
    }
    final guard =
        team.where((h) => h.skill.kind == 'guard').fold(0.0, (a, h) => a + h.skill.value);
    if (guard > 0) {
      final pct = (min(guard, 0.35) * 100).round();
      notes.add('Bulwark stack: team takes -$pct% damage');
    }
    if (team.length == 5) notes.add('Full team of 5: +10% damage');
    return notes;
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

  Future<String> username() async =>
      ((await _profile())['username'] ?? 'player') as String;

  Future<String?> avatarUrl() async =>
      (await _profile())['avatar_url'] as String?;
  Future<int> streakDays() async =>
      ((await _profile())['streak'] ?? 0) as int;
  Future<bool> isAdmin() async =>
      ((await _profile())['is_admin'] ?? false) as bool;

  Future<bool> claimedToday() async =>
      ((await _profile())['last_claim'] ?? '') == _today();

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, String>> artMap() async {
    final rows = await _sb.from('hero_art').select();
    return {
      for (final r in rows) r['name'] as String: r['picture'] as String,
    };
  }

  Future<List<Hero>> roster() async {
    final art = await artMap();
    final rows = await _sb
        .from('cards')
        .select()
        .eq('owner', _uid())
        .order('created_at');
    return rows.map((e) => Hero.fromRow(e, art: art)).toList();
  }

  Future<int> claimDaily() async {
    final r = await _sb.rpc('claim_daily');
    _bust();
    return (r as num).toInt();
  }

  Future<List<PullResult>> pull(int count) async {
    final rows = await _sb.rpc('gacha_pull', params: {'n': count}) as List;
    final art = await artMap();
    _bust();
    return rows
        .map((e) => PullResult(
            hero: Hero.fromRow(e, art: art)))
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

  Future<void> uploadAvatar(Uint8List bytes) async {
    final png = await compute(_toPng, bytes);
    final path = '${_uid()}/avatar.png';
    await _sb.storage.from('avatars').uploadBinary(
      path,
      png,
      fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
    );
    final url = _sb.storage.from('avatars').getPublicUrl(path);
    await _sb.rpc('set_avatar', params: {'url': url});
    _bust();
  }

  // ---------- admin ----------
  Future<void> adminGiveGold(String username, int amount) async {
    await _sb.rpc('give_gold',
        params: {'target_username': username, 'amount': amount});
  }

  Future<void> adminAddHero(int star, String name) async {
    await _sb.rpc('add_hero', params: {'star': star, 'name': name.trim()});
  }

  Future<void> adminRemoveHero(String name) async {
    await _sb.rpc('remove_hero', params: {'name': name.trim()});
  }

  Future<void> adminSetArt(String name, String url) async {
    await _sb.rpc('set_hero_art',
        params: {'hero_name': name.trim(), 'url': url.trim()});
  }

  // ---------- team persistence ----------
  Future<List<String>> loadTeam() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('g_team');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> saveTeam(List<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('g_team', jsonEncode(ids));
  }

  // ---------- battle ----------
  Future<BattleResult> battle(List<Hero> team, int requestedFloor) async {
    if (team.isEmpty) throw Exception('Pick at least one hero');
    final t = team.length > 5 ? team.sublist(0, 5) : team;
    final cleared = await floorCleared();
    final f = requestedFloor.clamp(1, cleared + 1);
    final (count, ePower) = waveInfo(f);

    final notes = comboNotes(t);
    final kinds = <String, int>{};
    for (final h in t) {
      kinds[h.skill.kind] = (kinds[h.skill.kind] ?? 0) + 1;
    }
    final boost = <String, double>{};
    for (final h in t) {
      var m = 1.0;
      if ((kinds[h.skill.kind] ?? 0) >= 2) m += 0.20;
      if (t.length == 5) m += 0.10;
      boost[h.id] = m;
    }
    final guard =
        t.where((h) => h.skill.kind == 'guard').fold(0.0, (a, h) => a + h.skill.value);
    final dmgTakenMul = 1.0 - min(guard, 0.35);

    final hF = <FighterInfo>[];
    final hMax = <int>[];
    final hHp = <int>[];
    final hAlive = <bool>[];
    for (var i = 0; i < t.length; i++) {
      hF.add(FighterInfo(
          id: 'H$i',
          name: t[i].name,
          power: t[i].power,
          star: t[i].star,
          picture: t[i].picture));
      hMax.add(t[i].power * 6);
      hHp.add(t[i].power * 6);
      hAlive.add(true);
    }
    final eF = <FighterInfo>[];
    final eMax = <int>[];
    final eHp = <int>[];
    final eAlive = <bool>[];
    for (var i = 0; i < count; i++) {
      eF.add(FighterInfo(
          id: 'E$i', name: _enemyAt(f, i, count), power: ePower));
      eMax.add(ePower * 6);
      eHp.add(ePower * 6);
      eAlive.add(true);
    }

    final events = <RoundEvent>[];
    var round = 1;
    while (round <= 40) {
      final hits = <HitEvent>[];

      for (var i = 0; i < t.length; i++) {
        if (!hAlive[i] || !eAlive.any((x) => x)) continue;
        final h = t[i];
        var dmg =
            h.power * (0.85 + _rng.nextDouble() * 0.3) * (boost[h.id] ?? 1.0);
        var crit = false;
        switch (h.skill.kind) {
          case 'damage':
            dmg *= 1 + h.skill.value;
          case 'first':
            if (round <= 3) dmg *= 1 + h.skill.value;
          case 'crit':
            if (_rng.nextDouble() < h.skill.value) {
              dmg *= 1.8;
              crit = true;
            }
        }
        var ti = -1;
        for (var j = 0; j < eF.length; j++) {
          if (eAlive[j] && (ti == -1 || eHp[j] < eHp[ti])) ti = j;
        }
        final d = dmg.round();
        eHp[ti] -= d;
        var heal = 0;
        if (h.skill.kind == 'lifesteal') {
          heal = (d * h.skill.value).round();
          hHp[i] = min(hMax[i], hHp[i] + heal);
        }
        final ko = eHp[ti] <= 0;
        if (ko) eAlive[ti] = false;
        hits.add(HitEvent(
          attackerId: hF[i].id,
          targetId: eF[ti].id,
          attackerName: hF[i].name,
          targetName: eF[ti].name,
          dmg: d,
          crit: crit,
          heal: heal,
          ko: ko,
          targetHpAfter: max(0, eHp[ti]),
        ));
      }

      for (var j = 0; j < eF.length; j++) {
        if (!eAlive[j] || !hAlive.any((x) => x)) continue;
        final ed = ePower * (0.85 + _rng.nextDouble() * 0.3) * dmgTakenMul;
        final alive = [for (var i = 0; i < hAlive.length; i++) if (hAlive[i]) i];
        final ti = alive[_rng.nextInt(alive.length)];
        final d = ed.round();
        hHp[ti] -= d;
        final ko = hHp[ti] <= 0;
        if (ko) hAlive[ti] = false;
        hits.add(HitEvent(
          attackerId: eF[j].id,
          targetId: hF[ti].id,
          attackerName: eF[j].name,
          targetName: hF[ti].name,
          dmg: d,
          crit: false,
          heal: 0,
          ko: ko,
          targetHpAfter: max(0, hHp[ti]),
        ));
      }

      if (hits.isNotEmpty) events.add(RoundEvent(round: round, hits: hits));
      if (!eAlive.any((x) => x) || !hAlive.any((x) => x)) break;
      round++;
    }

    final win = !eAlive.any((x) => x);
    final coins = await _sb.rpc('battle_result', params: {'f': f, 'won': win});
    _bust();
    return BattleResult(
      win: win,
      coins: (coins as num).toInt(),
      floor: f,
      heroes: hF,
      enemies: eF,
      events: events,
      comboNotes: notes,
    );
  }
}
