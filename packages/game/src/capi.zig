//! C-ABI shim for d2-game: one running game, headless, that a C/C++/C# host plays like a client —
//! a proxy for a live Diablo II server. NO Zig types cross the boundary: only C primitives, fixed
//! ints, pointers and `extern struct`s that must match `include/d2game.h`. Every export catches
//! all Zig errors and returns a negative status or null.
//!
//! A session is a GameInstance hosting one player. The host advances it in whole frames (25 a
//! second of game time, as fast as it likes), sends the commands a client would (walk, run, cast
//! at a point or a unit, drink from the belt, interact, or any raw C->S packet), and reads state
//! back as snapshots: the player, the monsters, missiles and objects of the player's level, the
//! belt, and how many monsters are still alive on a level (the Den of Evil's quest).
//!
//! The player comes from a `.d2s`: class, level, attributes, life/mana/stamina, experience, gold,
//! points, the 30 class skill levels plus item +skills, the equipped weapon's base damage and the
//! belt's potions. Without one it is a fresh level 1 sorceress.
//!
//! Allocator: page_allocator, as the other shims; the game is libc-free.

const std = @import("std");
const sim = @import("lib.zig");
const gs = sim.gameserver;
const save = @import("d2-save");
const d2data = @import("d2-data");

const pa = std.heap.page_allocator;

/// Must match `D2GameOptions` in d2game.h.
pub const D2GameOptions = extern struct {
    seed: u32,
    difficulty: i32, // 0 normal, 1 nightmare, 2 hell
    level_id: i32, // Levels.txt id the player starts in
    x: i32, // start position in world subtiles; 0,0 = the level's entry point
    y: i32,
};

/// Must match `D2GamePlayer` in d2game.h.
pub const D2GamePlayer = extern struct {
    unit_id: u32,
    class_id: i32,
    level_id: i32,
    x: i32,
    y: i32,
    level: i32,
    life: i32,
    max_life: i32,
    mana: i32,
    max_mana: i32,
    stamina: i32,
    max_stamina: i32,
    experience: i32,
    gold: i32,
    stat_points: i32,
    skill_points: i32,
    left_skill: i32,
    right_skill: i32,
    dead: i32,
    running: i32,
    moving: i32,
    kills: i32,
};

/// Must match `D2GameMonster` in d2game.h.
pub const D2GameMonster = extern struct {
    unit_id: u32,
    class_id: i32,
    x: i32,
    y: i32,
    life: i32,
    max_life: i32,
    alive: i32,
    rank: i32, // 0 normal, 1 champion, 2 unique, 3 superunique, 4 minion
    level: i32,
    npc: i32,
};

/// Must match `D2GameMissile` in d2game.h.
pub const D2GameMissile = extern struct {
    unit_id: u32,
    missile_id: i32,
    x: i32,
    y: i32,
    owner_id: u32,
};

/// Must match `D2GameObject` in d2game.h.
pub const D2GameObject = extern struct {
    unit_id: u32,
    class_id: i32,
    x: i32,
    y: i32,
    kind: i32, // 0 object, 1 warp
    dest_level: i32, // warps: the level it leads to
    operate_fn: i32, // objects: Objects.txt OperateFn (2 shrine, 4 chest, 8 door, ...)
};

/// Opaque running game.
pub const Session = struct {
    gi: gs.GameInstance,
    client: *gs.Client,
    skills: std.ArrayListUnmanaged(gs.PlayerSpec.SkillLevel) = .empty,
    name: [16]u8 = undefined,
};

fn diffFromInt(difficulty: i32) ?sim.world.Difficulty {
    return switch (difficulty) {
        0 => .normal,
        1 => .nightmare,
        2 => .hell,
        else => null,
    };
}

fn discardSink(_: i32, buf: []const u8) isize {
    return @intCast(buf.len);
}

/// Skills.txt id of a class's first skill: the 30 skill bytes of a save follow this order.
const CLASS_SKILL_BASE = [7]u16{ 6, 36, 66, 96, 126, 221, 251 };

/// Item stats that raise skill levels (ItemStatCost ids).
const STAT_ITEM_ALLSKILLS: u16 = 127;
const STAT_ITEM_CLASSSKILLS: u16 = 83; // param = class
const STAT_ITEM_SINGLESKILL: u16 = 107; // param = skill id
const STAT_ITEM_TABSKILLS: u16 = 188; // param = class * 8 + tab (class tabs of 10 skills)

/// The character a `.d2s` describes, as a PlayerSpec. `skills` is filled into `out_skills`, which
/// the spec borrows.
fn specFromSave(gpa: std.mem.Allocator, bytes: []const u8, out_skills: *std.ArrayListUnmanaged(gs.PlayerSpec.SkillLevel), name_buf: *[16]u8) !gs.PlayerSpec {
    const s = try save.parse(bytes);
    var spec = gs.PlayerSpec{};
    const class: u8 = @min(6, s.header.class);
    spec.class_id = class;
    const nm = s.header.nameSlice();
    const n = @min(nm.len, name_buf.len);
    @memcpy(name_buf[0..n], nm[0..n]);
    spec.name = name_buf[0..n];

    if (save.parseAttributes(bytes)) |a| {
        spec.level = @intCast(@max(1, a.level));
        spec.strength = @intCast(a.strength);
        spec.dexterity = @intCast(a.dexterity);
        spec.vitality = @intCast(a.vitality);
        spec.energy = @intCast(a.energy);
        spec.stat_points = @intCast(a.statpts);
        spec.skill_points = @intCast(a.newskills);
        spec.experience = @intCast(a.experience);
        spec.gold = @intCast(a.gold);
        // parseAttributes has already shifted the 8.8 life, mana and stamina down to whole points.
        spec.max_life = @intCast(a.maxhp);
        spec.life = @intCast(a.hp);
        spec.max_mana = @intCast(a.maxmana);
        spec.mana = @intCast(a.mana);
        spec.max_stamina = @intCast(a.maxstamina);
        spec.stamina = @intCast(a.stamina);
    } else {
        spec.level = s.header.level;
    }
    if (s.header.left_skill < sim.skill.MAX_SKILLS) spec.left_skill = @intCast(s.header.left_skill);
    if (s.header.right_skill < sim.skill.MAX_SKILLS) spec.right_skill = @intCast(s.header.right_skill);

    // Hard points: the 30 class skills in class order.
    var levels: [sim.skill.MAX_SKILLS]i16 = [_]i16{0} ** sim.skill.MAX_SKILLS;
    const base = CLASS_SKILL_BASE[class];
    for (s.skills.levels, 0..) |lv, i| {
        if (i >= 30) break;
        levels[base + i] += lv;
    }

    // Items: the equipped weapon's base damage, +skills from equipped gear, and the belt.
    var weapons = try sim.txt.Table.parse(gpa, d2data.file("Weapons"));
    defer weapons.deinit();
    var add_all: i16 = 0;
    var add_tab = [_]i16{0} ** 3;
    var it = s.items.iterator();
    while (it.next()) |item| {
        const code = item.code[0..@min(item.code_len, 4)];
        switch (item.dest) {
            1 => { // equipped
                if (item.body_loc == 4 or item.body_loc == 5) { // right / left hand
                    if (weapons.findByStr("code", code)) |row| {
                        const two = weapons.int(row, "2handmindam");
                        const one = weapons.int(row, "mindam");
                        if (one > 0) {
                            spec.weapon_min = @intCast(one);
                            spec.weapon_max = @intCast(weapons.int(row, "maxdam"));
                        } else if (two > 0) {
                            spec.weapon_min = @intCast(two);
                            spec.weapon_max = @intCast(weapons.int(row, "2handmaxdam"));
                        }
                    }
                }
                for (item.stats[0..item.n_stats]) |st| {
                    switch (st.id) {
                        STAT_ITEM_ALLSKILLS => add_all += @intCast(st.value),
                        STAT_ITEM_CLASSSKILLS => if (st.param == class) {
                            add_all += @intCast(st.value);
                        },
                        STAT_ITEM_SINGLESKILL => if (st.param < sim.skill.MAX_SKILLS) {
                            levels[st.param] += @intCast(st.value);
                        },
                        STAT_ITEM_TABSKILLS => if (st.param / 8 == class and st.param % 8 < 3) {
                            add_tab[st.param % 8] += @intCast(st.value);
                        },
                        else => {},
                    }
                }
            },
            2 => { // belt: x is the cell
                if (item.x < 16) {
                    var cell = gs.BeltCell{};
                    const cn = @min(code.len, 3);
                    @memcpy(cell.code[0..cn], code[0..cn]);
                    spec.belt[item.x] = cell;
                }
            },
            else => {},
        }
    }
    // +skills only raise skills the character has (a hard point, or an item's oskill).
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        const id = base + i;
        if (levels[id] > 0) levels[id] += add_all + add_tab[i / 10];
    }
    for (levels, 0..) |lv, id| {
        if (lv > 0) try out_skills.append(gpa, .{ .id = @intCast(id), .level = lv });
    }
    spec.skills = out_skills.items;
    return spec;
}

/// Why the last d2game_create on this thread failed ("" after a success).
threadlocal var g_last_error: [128]u8 = [_]u8{0} ** 128;

fn setError(comptime what: []const u8, err: ?anyerror) void {
    var buf: [128]u8 = undefined;
    const msg = if (err) |e| std.fmt.bufPrint(&buf, what ++ ": {s}", .{@errorName(e)}) catch what else what;
    const n = @min(msg.len, g_last_error.len - 1);
    @memcpy(g_last_error[0..n], msg[0..n]);
    g_last_error[n] = 0;
}

/// A NUL-terminated reason for the last failed d2game_create on this thread.
export fn d2game_last_error() [*:0]const u8 {
    return @ptrCast(&g_last_error);
}

export fn d2game_create(opt: ?*const D2GameOptions, d2s: ?[*]const u8, d2s_len: usize) ?*Session {
    setError("", null);
    const o = opt orelse {
        setError("no options", null);
        return null;
    };
    const diff = diffFromInt(o.difficulty) orelse {
        setError("difficulty is not 0, 1 or 2", null);
        return null;
    };
    const s = pa.create(Session) catch return null;
    s.* = .{ .gi = gs.GameInstance.init(pa, 1, o.seed, 0, diff), .client = undefined };
    s.gi.setLevel(@intCast(@max(1, o.level_id)));
    _ = s.gi.generateLevel() catch |e| {
        setError("generating the start level", e);
        s.gi.deinit();
        pa.destroy(s);
        return null;
    };
    var spec = gs.PlayerSpec{ .name = "Proxy", .skills = &.{} };
    if (d2s) |p| {
        if (d2s_len > 0) {
            spec = specFromSave(pa, p[0..d2s_len], &s.skills, &s.name) catch |e| {
                setError("reading the save", e);
                s.skills.deinit(pa);
                s.gi.deinit();
                pa.destroy(s);
                return null;
            };
        }
    }
    if (o.x != 0 or o.y != 0) spec.at = .{ o.x, o.y };
    s.client = s.gi.addPlayer(-1, spec) catch |e| {
        setError("joining the player", e);
        s.skills.deinit(pa);
        s.gi.deinit();
        pa.destroy(s);
        return null;
    };
    return s;
}

export fn d2game_destroy(session: ?*Session) void {
    const s = session orelse return;
    s.gi.deinit();
    s.skills.deinit(pa);
    pa.destroy(s);
}

/// Advance `frames` frames (25 a second of game time). Returns the frames run.
export fn d2game_step(session: ?*Session, frames: i32) i32 {
    const s = session orelse return -1;
    var i: i32 = 0;
    while (i < frames) : (i += 1) s.gi.tick(&discardSink);
    return i;
}

export fn d2game_frame(session: ?*const Session) u64 {
    const s = session orelse return 0;
    return s.gi.tick_count;
}

/// Send one raw C->S packet (the D2GS wire form). Returns the bytes consumed, 0 for an unknown or
/// short packet.
export fn d2game_send(session: ?*Session, bytes: ?[*]const u8, len: usize) i32 {
    const s = session orelse return -1;
    const b = bytes orelse return -1;
    return @intCast(s.gi.handleCommand(s.client, b[0..len]));
}

fn sendCoord(s: *Session, op: u8, x: i32, y: i32) i32 {
    var cmd: [5]u8 = undefined;
    cmd[0] = op;
    std.mem.writeInt(u16, cmd[1..3], @intCast(std.math.clamp(x, 0, 0xFFFF)), .little);
    std.mem.writeInt(u16, cmd[3..5], @intCast(std.math.clamp(y, 0, 0xFFFF)), .little);
    return @intCast(s.gi.handleCommand(s.client, &cmd));
}

fn sendEntity(s: *Session, op: u8, unit_id: u32) i32 {
    var cmd: [9]u8 = undefined;
    cmd[0] = op;
    std.mem.writeInt(u32, cmd[1..5], 1, .little); // unit type: monster
    std.mem.writeInt(u32, cmd[5..9], unit_id, .little);
    return @intCast(s.gi.handleCommand(s.client, &cmd));
}

/// Walk (run != 0: run) to a world subtile: C->S 0x01 / 0x03.
export fn d2game_walk(session: ?*Session, x: i32, y: i32, run: i32) i32 {
    const s = session orelse return -1;
    return sendCoord(s, if (run != 0) 0x03 else 0x01, x, y);
}

/// Stop where the player stands (drop its move target).
export fn d2game_stop(session: ?*Session) i32 {
    const s = session orelse return -1;
    const ls = s.gi.levels.get(s.client.level_id) orelse return -2;
    _ = ls.targets.remove(s.client.player_guid);
    return 0;
}

/// Put `skill_id` on the right (right != 0) or left hand: C->S 0x3C.
export fn d2game_select_skill(session: ?*Session, right: i32, skill_id: i32) i32 {
    const s = session orelse return -1;
    if (right != 0) s.client.right_skill = @intCast(skill_id) else s.client.left_skill = @intCast(skill_id);
    return 0;
}

/// Cast the right / left hand's skill at a world subtile: C->S 0x0C / 0x05.
export fn d2game_cast_at(session: ?*Session, right: i32, x: i32, y: i32) i32 {
    const s = session orelse return -1;
    return sendCoord(s, if (right != 0) 0x0C else 0x05, x, y);
}

/// Cast the right / left hand's skill on a unit: C->S 0x0D / 0x06.
export fn d2game_cast_on(session: ?*Session, right: i32, unit_id: u32) i32 {
    const s = session orelse return -1;
    return sendEntity(s, if (right != 0) 0x0D else 0x06, unit_id);
}

/// Drink the potion in belt cell `cell` (0..3 is the row the 1..4 keys use). 1 drunk, 0 not.
export fn d2game_use_belt(session: ?*Session, cell: i32) i32 {
    const s = session orelse return -1;
    if (cell < 0 or cell >= 16) return 0;
    return @intFromBool(s.gi.useBelt(s.client, @intCast(cell)));
}

/// Interact with a warp, object or NPC by unit id: C->S 0x13.
export fn d2game_interact(session: ?*Session, unit_id: u32) i32 {
    const s = session orelse return -1;
    var cmd: [9]u8 = undefined;
    cmd[0] = 0x13;
    std.mem.writeInt(u32, cmd[1..5], 2, .little); // unit type: object
    std.mem.writeInt(u32, cmd[5..9], unit_id, .little);
    return @intCast(s.gi.handleCommand(s.client, &cmd));
}

export fn d2game_player(session: ?*const Session, out: ?*D2GamePlayer) i32 {
    const s = session orelse return -1;
    const o = out orelse return -1;
    const ls = s.gi.levels.get(s.client.level_id) orelse return -2;
    const u = ls.units.getPtr(s.client.player_guid) orelse return -2;
    const tgt = ls.targets.get(s.client.player_guid);
    o.* = .{
        .unit_id = u.unit_id,
        .class_id = @intCast(u.class_id),
        .level_id = s.client.level_id,
        .x = u.x,
        .y = u.y,
        .level = u.get(.level),
        .life = u.life(),
        .max_life = u.get(.maxhp),
        .mana = u.get(.mana),
        .max_mana = u.get(.maxmana),
        .stamina = u.get(.stamina),
        .max_stamina = u.get(.maxstamina),
        .experience = u.get(.experience),
        .gold = u.get(.gold),
        .stat_points = u.get(.statpts),
        .skill_points = u.get(.newskills),
        .left_skill = s.client.left_skill,
        .right_skill = s.client.right_skill,
        .dead = @intFromBool(!u.isAlive()),
        .running = @intFromBool(if (tgt) |t| t.run else false),
        .moving = @intFromBool(tgt != null),
        .kills = @intCast(s.client.kills),
    };
    return 0;
}

/// The monsters of the player's level (alive and dead), up to `cap`. Returns how many there are
/// (which may exceed `cap`; call again with a bigger buffer).
export fn d2game_monsters(session: ?*const Session, out: ?[*]D2GameMonster, cap: i32) i32 {
    const s = session orelse return -1;
    const ls = s.gi.levels.get(s.client.level_id) orelse return -2;
    var n: i32 = 0;
    var it = ls.units.iterator();
    while (it.next()) |e| {
        const u = e.value_ptr;
        if (u.unit_type != .monster) continue;
        if (out) |o| {
            if (n < cap) {
                o[@intCast(n)] = .{
                    .unit_id = e.key_ptr.*,
                    .class_id = @intCast(u.class_id),
                    .x = u.x,
                    .y = u.y,
                    .life = u.life(),
                    .max_life = u.get(.maxhp),
                    .alive = @intFromBool(u.isAlive()),
                    .rank = @intFromEnum(u.rank),
                    .level = u.get(.level),
                    .npc = @intFromBool(ls.npcs.contains(e.key_ptr.*)),
                };
            }
        }
        n += 1;
    }
    return n;
}

export fn d2game_missiles(session: ?*const Session, out: ?[*]D2GameMissile, cap: i32) i32 {
    const s = session orelse return -1;
    const ls = s.gi.levels.get(s.client.level_id) orelse return -2;
    var n: i32 = 0;
    for (ls.missiles.items) |m| {
        if (out) |o| {
            if (n < cap) {
                o[@intCast(n)] = .{ .unit_id = m.guid, .missile_id = m.id, .x = m.x, .y = m.y, .owner_id = m.owner_id };
            }
        }
        n += 1;
    }
    return n;
}

/// The objects and warps of the player's level, up to `cap`; returns how many there are.
export fn d2game_objects(session: ?*const Session, out: ?[*]D2GameObject, cap: i32) i32 {
    const s = session orelse return -1;
    const ls = s.gi.levels.get(s.client.level_id) orelse return -2;
    var n: i32 = 0;
    for (ls.objects.items) |ob| {
        if (out) |o| {
            if (n < cap) {
                o[@intCast(n)] = .{ .unit_id = ob.guid, .class_id = ob.class_id, .x = ob.x, .y = ob.y, .kind = 0, .dest_level = 0, .operate_fn = ob.operate_fn };
            }
        }
        n += 1;
    }
    for (ls.warps.items) |w| {
        if (out) |o| {
            if (n < cap) {
                o[@intCast(n)] = .{ .unit_id = w.guid, .class_id = w.class_id, .x = w.x, .y = w.y, .kind = 1, .dest_level = w.dest_level, .operate_fn = 0 };
            }
        }
        n += 1;
    }
    return n;
}

/// The belt's 16 cells as 4-byte Misc.txt codes (NUL-padded; all zero = empty), into `out[64]`.
export fn d2game_belt(session: ?*const Session, out: ?[*]u8) i32 {
    const s = session orelse return -1;
    const o = out orelse return -1;
    for (s.client.belt, 0..) |cell, i| @memcpy(o[i * 4 ..][0..4], &cell.code);
    return 16;
}

/// The player's effective level in a skill (0 = it does not have it).
export fn d2game_skill_level(session: ?*const Session, skill_id: i32) i32 {
    const s = session orelse return -1;
    const book = s.client.book orelse return 0;
    if (skill_id < 0) return 0;
    return book.get(@intCast(skill_id));
}

/// Living hostile monsters on level `level_id` (its population when the player has not been there).
/// The Den of Evil's quest is done at 0.
export fn d2game_monsters_left(session: ?*Session, level_id: i32) i32 {
    const s = session orelse return -1;
    const ls = s.gi.ensureLevel(@intCast(level_id)) catch return -2;
    var n: i32 = 0;
    var it = ls.units.iterator();
    while (it.next()) |e| {
        const u = e.value_ptr;
        if (u.unit_type == .monster and u.isAlive() and u.owner_id == sim.unit.NO_OWNER and !ls.npcs.contains(e.key_ptr.*)) n += 1;
    }
    return n;
}

test "a session joins a fresh sorceress in the Den of Evil and plays frames" {
    const opt = D2GameOptions{ .seed = 1890709803, .difficulty = 0, .level_id = 8, .x = 0, .y = 0 };
    const s = d2game_create(&opt, null, 0) orelse return error.TestUnexpectedResult;
    defer d2game_destroy(s);
    var p: D2GamePlayer = undefined;
    try std.testing.expectEqual(@as(i32, 0), d2game_player(s, &p));
    try std.testing.expectEqual(@as(i32, 8), p.level_id);
    try std.testing.expect(d2game_monsters_left(s, 8) > 30);
    const before = p.x;
    _ = d2game_walk(s, p.x + 40, p.y, 0);
    try std.testing.expectEqual(@as(i32, 50), d2game_step(s, 50));
    _ = d2game_player(s, &p);
    try std.testing.expect(p.x != before or p.y != 0);
    try std.testing.expectEqual(@as(u64, 50), d2game_frame(s));
}

/// Must match `D2GameItem` in d2game.h.
pub const D2GameItem = extern struct {
    code: [4]u8, // NUL-padded
    dest: i32, // 0 stored, 1 equipped, 2 belt, 3 ground, 4 cursor, 6 socketed
    body_loc: i32, // equipped: 1 head, 2 neck, 3 torso, 4 right hand, 5 left hand, ... 8 belt, 9 feet
    x: i32, // belt: the cell; stored: the grid column
    y: i32,
    page: i32, // stored: 1 inventory, 4 cube, 5 stash
    quality: i32, // 1 low, 2 normal, 3 superior, 4 magic, 5 set, 6 rare, 7 unique, 8 crafted
    flags: u32,
    n_stats: i32,
    bit_len: i32,
};

/// The items of a `.d2s` (1.14d or D2R), up to `cap`: returns how many the player carries
/// including socketed ones, or a negative status for an unreadable save.
export fn d2game_save_items(bytes: ?[*]const u8, len: usize, out: ?[*]D2GameItem, cap: i32) i32 {
    const b = bytes orelse return -1;
    const s = save.parse(b[0..len]) catch return -2;
    var n: i32 = 0;
    var it = s.items.iterator();
    while (it.next()) |item| {
        if (out) |o| {
            if (n < cap) {
                var code = [_]u8{0} ** 4;
                @memcpy(code[0..item.code_len], item.code[0..item.code_len]);
                o[@intCast(n)] = .{
                    .code = code,
                    .dest = item.dest,
                    .body_loc = item.body_loc,
                    .x = item.x,
                    .y = item.y,
                    .page = item.page_raw,
                    .quality = @intFromEnum(item.quality),
                    .flags = item.flags,
                    .n_stats = item.n_stats,
                    .bit_len = @intCast(item.bit_len),
                };
            }
        }
        n += 1;
    }
    return n;
}
