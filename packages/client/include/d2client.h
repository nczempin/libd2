/* d2client — the client-side world model of libd2 (d2-client) behind a C ABI.
 *
 * Feed it the server->client game stream one whole packet at a time and read back what the stream
 * described: the local player, the units on the current level, every item. The list readers copy
 * at most `cap` records and return how many there are in all. See src/capi.zig. */
#ifndef D2CLIENT_H
#define D2CLIENT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct D2Client D2Client;

typedef struct D2ClientPlayer {
    uint32_t guid;
    int32_t class_id, level_id, x, y, level;
    int32_t life, max_life, mana, max_mana, stamina, max_stamina; /* whole points */
    int32_t experience, gold, stat_points, skill_points, mode;
    int32_t loaded; /* 1 once the act is loaded (0x04) */
} D2ClientPlayer;

typedef struct D2ClientUnit {
    int32_t unit_type; /* 0 player, 1 monster, 2 object, 5 warp */
    uint32_t guid;
    int32_t class_id, x, y;
    int32_t life; /* 0..128 */
    int32_t mode, level_id, is_warp;
} D2ClientUnit;

typedef struct D2ClientItem {
    uint32_t guid;
    uint8_t code[4];
    int32_t where; /* 0 stored, 1 equipped, 2 belt, 3 ground, 4 cursor, 5 dropped, 6 socketed */
    uint32_t owner;
    int32_t x, y, page, body_loc, quality, quantity;
    uint32_t flags;
} D2ClientItem;

D2Client* d2client_create(void);
void d2client_destroy(D2Client* client);
void d2client_set_local_name(D2Client* client, const char* name);
void d2client_apply(D2Client* client, const uint8_t* packet, int32_t len);
int32_t d2client_player(const D2Client* client, D2ClientPlayer* out);
int32_t d2client_units(const D2Client* client, int32_t unit_type, D2ClientUnit* out, int32_t cap);
int32_t d2client_items(const D2Client* client, D2ClientItem* out, int32_t cap);
int32_t d2client_level(const D2Client* client, uint32_t* map_seed);
uint32_t d2client_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif
