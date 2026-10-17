//! C-ABI shim for the d2-client package: the client-side world model — feed it the server->client
//! stream one packet at a time and read back what the stream described — for C/C++/C#/Go/Node.
//!
//! A handle owns one `World`. Nothing crosses the boundary but C primitives and `extern struct`s
//! the caller owns; the list readers copy at most `cap` records into the caller's array and return
//! how many there are in all, so a caller can size its buffer from a first call.
//!
//! Allocator: page_allocator, as the other shims.

const std = @import("std");
const client = @import("d2-client");
const World = client.World;

const pa = std.heap.page_allocator;

pub const Handle = struct {
    world: World,
};

/// Must match `D2ClientPlayer` in d2client.h. Life, mana and stamina are whole points; the
/// maxima come from the stat packets (the engine's <<8 fixed point is removed).
pub const D2ClientPlayer = extern struct {
    guid: u32,
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
    mode: i32,
    /// 1 once the server has said the act is loaded (0x04), 0 before and after.
    loaded: i32,
};

/// Must match `D2ClientUnit` in d2client.h. `life` is the wire's 0..128 scale (128 = full).
pub const D2ClientUnit = extern struct {
    unit_type: i32,
    guid: u32,
    class_id: i32,
    x: i32,
    y: i32,
    life: i32,
    mode: i32,
    level_id: i32,
    is_warp: i32,
};

/// Must match `D2ClientItem` in d2client.h. `where` is the model's `Where` (0 stored, 1 equipped,
/// 2 belt, 3 ground, 4 cursor, 5 dropped, 6 socketed); `x`/`y` are the grid cell, or the world
/// position on the ground; `page` is the raw page field (0 in no grid, else page + 1).
pub const D2ClientItem = extern struct {
    guid: u32,
    code: [4]u8,
    where: i32,
    owner: u32,
    x: i32,
    y: i32,
    page: i32,
    body_loc: i32,
    quality: i32,
    quantity: i32,
    flags: u32,
};

export fn d2client_create() ?*Handle {
    const h = pa.create(Handle) catch return null;
    h.* = .{ .world = World.init(pa) };
    return h;
}

export fn d2client_destroy(handle: ?*Handle) void {
    const h = handle orelse return;
    h.world.deinit();
    pa.destroy(h);
}

/// Name the character being played, so the model can tell its player from any other.
export fn d2client_set_local_name(handle: ?*Handle, name: ?[*:0]const u8) void {
    const h = handle orelse return;
    const n = name orelse return;
    h.world.expectLocalPlayer(std.mem.span(n));
}

/// Apply one whole server->client packet (`buf[0]` is its opcode).
export fn d2client_apply(handle: ?*Handle, buf: ?[*]const u8, len: i32) void {
    const h = handle orelse return;
    const p = buf orelse return;
    if (len <= 0) return;
    h.world.apply(p[0..@intCast(len)]);
}

fn stat(w: *const World, id: u16) i32 {
    return w.player_stats.get(id) orelse 0;
}

/// The local player. Returns 1, or 0 while the stream has not yet named one.
export fn d2client_player(handle: ?*const Handle, out: ?*D2ClientPlayer) i32 {
    const h = handle orelse return 0;
    const o = out orelse return 0;
    const w = &h.world;
    const guid = w.local_player_guid orelse return 0;
    const u = w.getUnit(.player, guid) orelse return 0;
    o.* = .{
        .guid = guid,
        .class_id = u.class_id,
        .level_id = w.level_id,
        .x = u.x,
        .y = u.y,
        .level = stat(w, 12),
        .life = w.local_hp,
        .max_life = stat(w, 7) >> 8,
        .mana = w.local_mp,
        .max_mana = stat(w, 9) >> 8,
        .stamina = w.local_stamina,
        .max_stamina = stat(w, 11) >> 8,
        .experience = stat(w, 13),
        .gold = stat(w, 14),
        .stat_points = stat(w, 4),
        .skill_points = stat(w, 5),
        .mode = u.mode,
        .loaded = @intFromBool(w.loaded),
    };
    return 1;
}

/// The units the stream has described on the current level, of `unit_type` (0 player, 1 monster,
/// 2 object, 5 warp) or of every type when it is negative. Copies up to `cap` into `out` and
/// returns how many there are.
export fn d2client_units(handle: ?*const Handle, unit_type: i32, out: ?[*]D2ClientUnit, cap: i32) i32 {
    const h = handle orelse return 0;
    const w = &h.world;
    var n: i32 = 0;
    var it = w.units.valueIterator();
    while (it.next()) |u| {
        if (unit_type >= 0 and u.utype != unit_type) continue;
        if (!w.onThisLevel(u)) continue;
        if (out) |o| {
            if (n < cap) o[@intCast(n)] = .{
                .unit_type = u.utype,
                .guid = u.guid,
                .class_id = u.class_id,
                .x = u.x,
                .y = u.y,
                .life = u.life,
                .mode = u.mode,
                .level_id = u.level,
                .is_warp = @intFromBool(u.is_warp),
            };
        }
        n += 1;
    }
    return n;
}

/// Every item the stream has described and not taken out of the world. Copies up to `cap` into
/// `out` and returns how many there are.
export fn d2client_items(handle: ?*const Handle, out: ?[*]D2ClientItem, cap: i32) i32 {
    const h = handle orelse return 0;
    var n: i32 = 0;
    var it = h.world.items.iterator();
    while (it.next()) |e| {
        const owned = e.value_ptr.*;
        if (owned.where == .gone) continue;
        if (out) |o| {
            if (n < cap) {
                const item = owned.item;
                o[@intCast(n)] = .{
                    .guid = e.key_ptr.*,
                    .code = item.code,
                    .where = @intFromEnum(owned.where),
                    .owner = owned.owner,
                    .x = item.x,
                    .y = item.y,
                    .page = item.page_raw,
                    .body_loc = item.body_loc,
                    .quality = @intFromEnum(item.quality),
                    .quantity = item.quantity,
                    .flags = item.flags,
                };
            }
        }
        n += 1;
    }
    return n;
}

/// The current level (Levels.txt id) and act's map seed.
export fn d2client_level(handle: ?*const Handle, map_seed: ?*u32) i32 {
    const h = handle orelse return 0;
    if (map_seed) |s| s.* = h.world.map_seed;
    return h.world.level_id;
}

export fn d2client_abi_version() u32 {
    return 1;
}

test "a created player is read back with its class and position" {
    const h = d2client_create() orelse return error.OutOfMemory;
    defer d2client_destroy(h);
    d2client_set_local_name(h, "Hostbot");
    var p59 = [_]u8{0} ** 26;
    p59[0] = 0x59;
    std.mem.writeInt(u32, p59[1..5], 1, .little);
    p59[5] = 1; // sorceress
    @memcpy(p59[6..13], "Hostbot");
    std.mem.writeInt(u16, p59[22..24], 5663, .little);
    std.mem.writeInt(u16, p59[24..26], 5813, .little);
    d2client_apply(h, &p59, p59.len);
    var p: D2ClientPlayer = undefined;
    try std.testing.expectEqual(@as(i32, 1), d2client_player(h, &p));
    try std.testing.expectEqual(@as(u32, 1), p.guid);
    try std.testing.expectEqual(@as(i32, 1), p.class_id);
    try std.testing.expectEqual(@as(i32, 5663), p.x);
    try std.testing.expectEqual(@as(i32, 5813), p.y);
}
