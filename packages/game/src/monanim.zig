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

test "built-in timings" {
    try std.testing.expectEqual(@as(u8, 10), timing("FA").a1);
    try std.testing.expectEqual(@as(u8, 7), timing("fa").a1_hit);
    try std.testing.expectEqual(DEFAULT.a1, timing("XX").a1);
}
