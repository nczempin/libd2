//! Monster animation timing and melee reach — what paces a monster's fight.
//!
//! A monster acts in modes (MONMODE): an attack plays its animation and lands its hit on the
//! animation's hit frame, a hit taken plays the get-hit animation, and when a mode ends the
//! monster's next AI think comes `aidel` frames later (D2MOO MonsterMode.cpp, the mode-end
//! handler at D2Game.0x6FC64310). The animation lengths and hit frames live in animdata.d2, one
//! record per COF (monster code + mode + weapon class: "FAA1HTH"). That file is not part of the
//! txt tables, so the timings the Act 1 Den of Evil needs are built in here, read from
//! animdata.d2; a monster without an entry gets `DEFAULT`.
//!
//! Melee reach is UNITS_IsInMeleeRange (D2Common Units.cpp): the size-aware unit distance
//! D2Common_10399 at most MeleeRng + 1.

const std = @import("std");

/// One monster's mode lengths in game frames (animation frames x 256 / animation speed) and the
/// frame of its attacks' hit (counted from the mode's start).
pub const Timing = struct {
    a1: u8,
    a1_hit: u8,
    a2: u8,
    a2_hit: u8,
    /// Skill2 (the Fallen's taunt): no hit.
    s2: u8,
    gh: u8,
    /// The death animation: a corpse in it is still "dying" (MONMODE_DEATH).
    dt: u8,
};

pub const DEFAULT: Timing = .{ .a1 = 12, .a1_hit = 6, .a2 = 12, .a2_hit = 6, .s2 = 12, .gh = 6, .dt = 20 };

const Entry = struct { code: []const u8, t: Timing };

/// From animdata.d2 (D2R 3.x): <code>A1HTH, A2HTH, S2HTH, GHHTH, DTHTH.
const BUILT_IN = [_]Entry{
    // Fallen / Carver / Devilkin / Dark One / Warped Fallen
    .{ .code = "FA", .t = .{ .a1 = 10, .a1_hit = 7, .a2 = 15, .a2_hit = 8, .s2 = 18, .gh = 7, .dt = 20 } },
    // Fallen Shaman family (A2 is its fire cast)
    .{ .code = "FS", .t = .{ .a1 = 17, .a1_hit = 8, .a2 = 17, .a2_hit = 8, .s2 = 17, .gh = 5, .dt = 21 } },
    // Zombie family (GH at speed 152, DT at 208)
    .{ .code = "ZM", .t = .{ .a1 = 16, .a1_hit = 9, .a2 = 16, .a2_hit = 9, .s2 = 16, .gh = 8, .dt = 23 } },
    // Gargantuan Beast / Brute family
    .{ .code = "YE", .t = .{ .a1 = 12, .a1_hit = 5, .a2 = 18, .a2_hit = 9, .s2 = 12, .gh = 6, .dt = 18 } },
};

pub fn timing(code: []const u8) Timing {
    for (BUILT_IN) |e| if (std.ascii.eqlIgnoreCase(e.code, code)) return e.t;
    return DEFAULT;
}

/// A player class's cast and get-hit animations (animdata.d2 <class>SCHTH and <class>GHHTH: frames
/// per direction, the cast's release frame and animation rate), by class id.
const PlayerAnim = struct { sc: u16, sc_release: u16, sc_rate: u16, gh: u16 };
const PLAYER_ANIM = [7]PlayerAnim{
    .{ .sc = 20, .sc_release = 11, .sc_rate = 256, .gh = 6 }, // Amazon
    .{ .sc = 14, .sc_release = 7, .sc_rate = 256, .gh = 8 }, // Sorceress
    .{ .sc = 16, .sc_release = 8, .sc_rate = 256, .gh = 7 }, // Necromancer
    .{ .sc = 16, .sc_release = 9, .sc_rate = 256, .gh = 5 }, // Paladin
    .{ .sc = 14, .sc_release = 9, .sc_rate = 256, .gh = 5 }, // Barbarian
    .{ .sc = 15, .sc_release = 8, .sc_rate = 208, .gh = 7 }, // Druid
    .{ .sc = 17, .sc_release = 9, .sc_rate = 256, .gh = 5 }, // Assassin
};

/// The diminishing return on faster cast / hit recovery: 120 x / (120 + x).
fn effective(x: i32) i32 {
    if (x <= 0) return 0;
    return @divTrunc(120 * x, 120 + x);
}

fn ceilDiv(a: i32, b: i32) i32 {
    return @divTrunc(a + b - 1, b);
}

pub const CastTiming = struct { frames: u64, release: u64 };

/// A cast's length and its release frame in game frames: ceil(256 frames / speed) - 1, the speed the
/// animation rate times (100 + effective FCR) / 100. A sorceress at 0% casts in 13 frames, at 9% in 12.
pub fn playerCast(class_id: i32, fcr: i32) CastTiming {
    const a = PLAYER_ANIM[@intCast(std.math.clamp(class_id, 0, 6))];
    const speed: i32 = @max(1, @divTrunc(@as(i32, a.sc_rate) * (100 + effective(fcr)), 100));
    return .{
        .frames = @intCast(@max(1, ceilDiv(256 * @as(i32, a.sc), speed) - 1)),
        .release = @intCast(@divTrunc(256 * @as(i32, a.sc_release), speed)),
    };
}

/// Hit recovery in game frames: get-hit runs at half rate, so ceil(256 frames / speed) - 1 with
/// speed 256 (50 + effective FHR) / 100. A sorceress at 0% recovers in 15 frames, at 5% in 14.
pub fn playerGetHit(class_id: i32, fhr: i32) u64 {
    const a = PLAYER_ANIM[@intCast(std.math.clamp(class_id, 0, 6))];
    const speed: i32 = @divTrunc(256 * (50 + effective(fhr)), 100);
    return @intCast(@max(1, ceilDiv(256 * @as(i32, a.gh), speed) - 1));
}

/// The get-hit gate (sub_6FCC1870) for `lost` life of `maxhp`, with the attack's hit-class divisor
/// (16 for most): under maxhp / d never, under 2 maxhp / d half the time, under 4 maxhp / d three
/// times in four, above it always. `roll` is a random number; under one point of life never.
pub fn hitRecovers(lost: i32, maxhp: i32, divisor: i32, roll: u32) bool {
    if (lost < 1) return false;
    if (lost < @divTrunc(maxhp, divisor)) return false;
    if (lost < @divTrunc(maxhp, @divTrunc(divisor, 2))) return roll & 1 != 0;
    if (lost < @divTrunc(maxhp, @divTrunc(divisor, 4))) return roll & 3 != 0;
    return true;
}

/// D2Common_10399: the distance between two units' edges, from the subtile deltas and the units'
/// SizeX (a player is 2). Near units read a lookup table; far or big ones a chamfer distance.
pub fn unitDistance(dx_in: i32, dy_in: i32, size1: i32, size2: i32) i32 {
    const near = [_]i8{
        -1, -1, -1, 0, 2, 4, 6,  8,
        -1, -1, 0,  1, 2, 4, 6,  8,
        -1, 0,  0,  2, 3, 5, 7,  8,
        0,  1,  2,  2, 4, 5, 7,  8,
        2,  2,  3,  4, 5, 6, 7,  9,
        4,  4,  5,  5, 6, 7, 8,  9,
        6,  6,  7,  7, 7, 8, 10, 10,
        8,  8,  8,  8, 9, 9, 10, 11,
    };
    const dx: i32 = @intCast(@abs(dx_in));
    const dy: i32 = @intCast(@abs(dy_in));
    if (dx >= 8 or dy >= 8 or size1 >= 4 or size2 >= 4) {
        const sd: i32 = (@divTrunc(size2, 2)) + (@divTrunc(size1, 2));
        const x = @max(0, dx - sd);
        const y = @max(0, dy - sd);
        return if (x <= y) x + 2 * y else y + 2 * x;
    }
    var d: i32 = near[@intCast(dx + 8 * dy)];
    if (d < 0) return 0;
    if (size1 == 3 or size2 == 3) d -= 1;
    if (d < 0) d = 0;
    if (size1 <= 1 or size2 <= 1) d += 1;
    return d;
}

/// UNITS_IsInMeleeRange without its collision test: in reach at a unit distance of at most
/// MeleeRng + 1 (0 counts as touching).
pub fn inMeleeRange(dx: i32, dy: i32, size1: i32, size2: i32, melee_rng: i32) bool {
    const d = unitDistance(dx, dy, size1, size2);
    return d <= 0 or melee_rng + 1 >= d;
}

test "a Fallen reaches the player about three subtiles away" {
    // two size-2 units: touching along an axis up to 3 subtiles apart, out of reach at 4
    try std.testing.expect(inMeleeRange(3, 0, 2, 2, 0));
    try std.testing.expect(inMeleeRange(2, 2, 2, 2, 0));
    try std.testing.expect(!inMeleeRange(4, 0, 2, 2, 0));
    try std.testing.expect(!inMeleeRange(3, 3, 2, 2, 0));
    // a size-3 Gargantuan Beast reaches one subtile farther
    try std.testing.expect(inMeleeRange(4, 0, 3, 2, 0));
}

test "player cast and hit recovery frames match the class breakpoints" {
    // 0% FCR: Amazon 19, Sorceress 13, Necromancer 15, Paladin 15, Barbarian 13, Druid 18, Assassin 16
    const want = [_]u64{ 19, 13, 15, 15, 13, 18, 16 };
    for (want, 0..) |f, cls| try std.testing.expectEqual(f, playerCast(@intCast(cls), 0).frames);
    try std.testing.expectEqual(@as(u64, 12), playerCast(1, 9).frames);
    try std.testing.expectEqual(@as(u64, 7), playerCast(1, 0).release);
    // 0% FHR: Amazon 11, Sorceress 15, Necromancer 13, Paladin 9, Barbarian 9, Druid 13, Assassin 9
    const gh = [_]u64{ 11, 15, 13, 9, 9, 13, 9 };
    for (gh, 0..) |f, cls| try std.testing.expectEqual(f, playerGetHit(@intCast(cls), 0));
    try std.testing.expectEqual(@as(u64, 14), playerGetHit(1, 5));
    try std.testing.expectEqual(@as(u64, 13), playerGetHit(1, 9));
}

test "the get-hit gate's tiers" {
    try std.testing.expect(!hitRecovers(2, 64, 16, 3)); // under 1/16
    try std.testing.expect(hitRecovers(5, 64, 16, 1) and !hitRecovers(5, 64, 16, 2)); // 1/16..1/8: odd rolls
    try std.testing.expect(hitRecovers(9, 64, 16, 1) and !hitRecovers(9, 64, 16, 4)); // 1/8..1/4: rolls not 0 mod 4
    try std.testing.expect(hitRecovers(16, 64, 16, 0)); // 1/4 and more
}

test "built-in timings" {
    try std.testing.expectEqual(@as(u8, 10), timing("FA").a1);
    try std.testing.expectEqual(@as(u8, 7), timing("fa").a1_hit);
    try std.testing.expectEqual(DEFAULT.a1, timing("XX").a1);
}
