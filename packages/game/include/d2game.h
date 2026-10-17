/*
 * d2game — one headless Diablo II 1.14d game a host plays like a client: a proxy for a live
 * server. See packages/game/src/capi.zig for the behaviour behind each call.
 *
 * Positions are world subtiles, the coordinates the game sends a client. Time advances only in
 * d2game_step, in frames of 1/25 s of game time, as fast as the host calls it. Calls that return
 * int32_t return a negative status on a bad handle or argument.
 */
#ifndef D2GAME_H
#define D2GAME_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct D2Game D2Game;

typedef struct D2GameOptions {
    uint32_t seed;
    int32_t difficulty; /* 0 normal, 1 nightmare, 2 hell */
    int32_t level_id;   /* Levels.txt id the player starts in */
    int32_t x, y;       /* start position; 0,0 = the level's entry point */
} D2GameOptions;

typedef struct D2GamePlayer {
    uint32_t unit_id;
    int32_t class_id, level_id, x, y;
    int32_t level, life, max_life, mana, max_mana, stamina, max_stamina;
    int32_t experience, gold, stat_points, skill_points;
    int32_t left_skill, right_skill;
    int32_t dead, running, moving, kills;
} D2GamePlayer;

typedef struct D2GameMonster {
    uint32_t unit_id;
    int32_t class_id, x, y, life, max_life, alive;
    int32_t rank; /* 0 normal, 1 champion, 2 unique, 3 superunique, 4 minion */
    int32_t level, npc;
} D2GameMonster;

typedef struct D2GameMissile {
    uint32_t unit_id;
    int32_t missile_id, x, y;
    uint32_t owner_id;
} D2GameMissile;

typedef struct D2GameObject {
    uint32_t unit_id;
    int32_t class_id, x, y;
    int32_t kind;       /* 0 object, 1 warp */
    int32_t dest_level; /* warps */
    int32_t operate_fn; /* objects: Objects.txt OperateFn */
} D2GameObject;

/* A game on `opt`, with the player from a .d2s (null / 0 length: a fresh level 1 sorceress). */
D2Game *d2game_create(const D2GameOptions *opt, const uint8_t *d2s, size_t d2s_len);
void d2game_destroy(D2Game *game);

/* Advance `frames` frames; returns the frames run. */
int32_t d2game_step(D2Game *game, int32_t frames);
uint64_t d2game_frame(const D2Game *game);

/* Commands. */
int32_t d2game_walk(D2Game *game, int32_t x, int32_t y, int32_t run);
int32_t d2game_stop(D2Game *game);
int32_t d2game_select_skill(D2Game *game, int32_t right, int32_t skill_id);
int32_t d2game_cast_at(D2Game *game, int32_t right, int32_t x, int32_t y);
int32_t d2game_cast_on(D2Game *game, int32_t right, uint32_t unit_id);
int32_t d2game_use_belt(D2Game *game, int32_t cell); /* 1 drunk, 0 not */
int32_t d2game_interact(D2Game *game, uint32_t unit_id);
int32_t d2game_send(D2Game *game, const uint8_t *bytes, size_t len); /* a raw C->S packet */

/* State. The list calls return how many there are, which may exceed `cap`. */
int32_t d2game_player(const D2Game *game, D2GamePlayer *out);
int32_t d2game_monsters(const D2Game *game, D2GameMonster *out, int32_t cap);
int32_t d2game_missiles(const D2Game *game, D2GameMissile *out, int32_t cap);
int32_t d2game_objects(const D2Game *game, D2GameObject *out, int32_t cap);
int32_t d2game_belt(const D2Game *game, uint8_t out[64]); /* 16 cells x 4-byte Misc.txt code */
int32_t d2game_skill_level(const D2Game *game, int32_t skill_id);
int32_t d2game_monsters_left(D2Game *game, int32_t level_id);

#ifdef __cplusplus
}
#endif

#endif
