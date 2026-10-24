/* WebAssembly exports for the browser preview (built by build_wasm.sh). */
#include <stdint.h>

#include "sim.h"
#include "sohail/button.h"
#include "sohail/chime.h"
#include "sohail/protocol.h"

#define EXPORT(name) __attribute__((export_name(name)))

static char s_name[SOHAIL_NAME_MAX + 1];
static char s_text[SOHAIL_TEXT_MAX + 1];
static char s_json[1024]; /* MQTT payloads in and out (the firmware's limit) */
static char s_id[SOHAIL_ID_MAX + 1];
static int16_t s_audio[SIM_SAMPLE_RATE]; /* every chime is under a second */
static button_t s_button;

EXPORT("name_buf") char *name_buf(void) { return s_name; }
EXPORT("text_buf") char *text_buf(void) { return s_text; }
EXPORT("json_buf") char *json_buf(void) { return s_json; }
EXPORT("json_buf_len") int json_buf_len(void) { return (int)sizeof(s_json); }
EXPORT("id_buf") char *id_buf(void) { return s_id; }

/* Identity from id_buf (device id) and name_buf. 1 on success. */
EXPORT("set_identity") int w_set_identity(void) { return sim_set_identity(s_id, s_name) ? 1 : 0; }

/* Deliver the len-byte MQTT payload in json_buf. Flags, or -1 if rejected. */
EXPORT("receive_json") int w_receive_json(int len, uint32_t now)
{
    if (len < 0 || len > (int)sizeof(s_json)) return -1;
    return sim_receive_json(s_json, (size_t)len, now);
}

/* Encode the last send into json_buf with message id from id_buf. */
EXPORT("encode_last_send") int w_encode_last_send(uint32_t unix_ts)
{
    char msg_id[SOHAIL_ID_MAX + 1];
    for (int i = 0; i <= SOHAIL_ID_MAX; i++) msg_id[i] = s_id[i];
    return sim_encode_last_send(msg_id, unix_ts, s_json, sizeof(s_json));
}

EXPORT("init") void w_init(uint32_t seed, uint32_t now)
{
    sim_init(seed, now);
    button_init(&s_button);
}

/*
 * Feeds the on-page button through the firmware's gesture decoder (call every
 * ~10 ms). Returns -1 if nothing happened, else (action_flags << 8) | event,
 * where event is the robot_event_type_t that was posted.
 */
EXPORT("button") int w_button(int pressed, uint32_t now)
{
    static const robot_event_type_t MAP[] = {
        [BUTTON_SHORT] = EV_BTN_SHORT,
        [BUTTON_DOUBLE] = EV_BTN_DOUBLE,
        [BUTTON_HOLD] = EV_BTN_HOLD,
        [BUTTON_LONG] = EV_BTN_LONG,
        [BUTTON_HOLD_RELEASED] = EV_BTN_HOLD_RELEASED,
    };
    button_event_t e = button_update(&s_button, pressed != 0, now);
    if (e == BUTTON_NONE) {
        return -1;
    }
    uint32_t flags = sim_post(MAP[e], now);
    return (int)((flags << 8) | MAP[e]);
}
EXPORT("post") uint32_t w_post(int type, uint32_t now) { return sim_post(type, now); }
EXPORT("start_provisioning") uint32_t w_prov(uint32_t now) { return sim_start_provisioning(s_text, now); }
EXPORT("receive") uint32_t w_receive(int type, int emoji, uint32_t now)
{
    return sim_receive(type, emoji, s_name, s_text, now);
}
EXPORT("tick") uint32_t w_tick(uint32_t now) { return sim_tick(now); }
EXPORT("last_chime") int w_last_chime(void) { return sim_last_chime(); }
EXPORT("last_send_type") int w_last_send_type(void) { return sim_last_send_type(); }
EXPORT("last_send_emoji") int w_last_send_emoji(void) { return sim_last_send_emoji(); }
EXPORT("render") void w_render(uint32_t now) { sim_render(now); }
EXPORT("framebuffer") uint16_t *w_framebuffer(void) { return sim_framebuffer(); }
EXPORT("state_name") const char *w_state_name(void) { return sim_state_name(); }
EXPORT("unread") int w_unread(void) { return sim_robot()->inbox_count; }
EXPORT("emoji_name") const char *w_emoji_name(int e) { return sohail_emoji_name((sohail_emoji_t)e); }

/* Renders a chime into the audio buffer; returns the sample count. */
EXPORT("chime") int w_chime(int chime, int volume)
{
    return (int)chime_render((chime_t)chime, SIM_SAMPLE_RATE, (uint8_t)volume, 0, s_audio,
                             sizeof(s_audio) / sizeof(s_audio[0]));
}
EXPORT("audio_buf") int16_t *w_audio_buf(void) { return s_audio; }
