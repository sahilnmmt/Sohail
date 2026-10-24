#include "sim.h"

#include <stdio.h>
#include <string.h>

#include "sohail/chime.h"
#include "sohail/protocol.h"
#include "sohail/screen.h"

static char s_self_id[SOHAIL_ID_MAX + 1] = "sohail-sim001";
static char s_name[SOHAIL_NAME_MAX + 1] = "Virtual robot";

static robot_t s_robot;
static screen_t s_screen;
static robot_actions_t s_last;
static uint16_t s_fb[SIM_W * SIM_H];
static int s_msg_seq;

void sim_init(uint32_t seed, uint32_t now_ms)
{
    robot_init(&s_robot, s_self_id, now_ms);
    screen_init(&s_screen, SIM_W, SIM_H, seed);
    memset(&s_last, 0, sizeof(s_last));
    s_last.chime = -1;
    s_msg_seq = 0;
}

static uint32_t handle(const robot_event_t *ev, uint32_t now_ms)
{
    robot_actions_t act;
    robot_handle(&s_robot, ev, now_ms, &act);
    if (act.flags) {
        s_last = act;
        if (!(act.flags & ACT_CHIME)) {
            s_last.chime = -1;
        }
    }
    return act.flags;
}

uint32_t sim_post(int type, uint32_t now_ms)
{
    robot_event_t ev = {.type = (robot_event_type_t)type};
    return handle(&ev, now_ms);
}

uint32_t sim_start_provisioning(const char *code, uint32_t now_ms)
{
    robot_event_t ev = {.type = EV_PROV_START};
    snprintf(ev.prov_code, sizeof(ev.prov_code), "%s", code);
    return handle(&ev, now_ms);
}

uint32_t sim_receive(int type, int emoji, const char *name, const char *text, uint32_t now_ms)
{
    robot_event_t ev = {.type = EV_MSG};
    snprintf(ev.msg.id, sizeof(ev.msg.id), "sim-%d", ++s_msg_seq);
    snprintf(ev.msg.from, sizeof(ev.msg.from), "sohail-peer01");
    snprintf(ev.msg.name, sizeof(ev.msg.name), "%s", name ? name : "");
    ev.msg.type = (sohail_msg_type_t)type;
    ev.msg.emoji = (sohail_emoji_t)emoji;
    snprintf(ev.msg.text, sizeof(ev.msg.text), "%s", text ? text : "");
    return handle(&ev, now_ms);
}

bool sim_set_identity(const char *device_id, const char *name)
{
    if (!sohail_id_valid(device_id) || strlen(name) > SOHAIL_NAME_MAX) {
        return false;
    }
    snprintf(s_self_id, sizeof(s_self_id), "%s", device_id);
    snprintf(s_name, sizeof(s_name), "%s", name);
    return true;
}

int sim_receive_json(const char *json, size_t len, uint32_t now_ms)
{
    robot_event_t ev = {.type = EV_MSG};
    if (sohail_msg_decode(json, len, &ev.msg) != SOHAIL_OK) {
        return -1;
    }
    return (int)handle(&ev, now_ms);
}

int sim_encode_last_send(const char *msg_id, uint32_t unix_ts, char *out, size_t out_len)
{
    sohail_msg_t m = {.type = s_last.send_type, .emoji = s_last.send_emoji, .ts = unix_ts};
    snprintf(m.id, sizeof(m.id), "%s", msg_id);
    snprintf(m.from, sizeof(m.from), "%s", s_self_id);
    snprintf(m.name, sizeof(m.name), "%s", s_name);
    return sohail_msg_encode(&m, out, out_len);
}

uint32_t sim_tick(uint32_t now_ms)
{
    return sim_post(EV_TICK, now_ms);
}

int sim_last_chime(void) { return s_last.chime; }
int sim_last_send_type(void) { return s_last.send_type; }
int sim_last_send_emoji(void) { return s_last.send_emoji; }

void sim_render(uint32_t now_ms)
{
    robot_view_t view;
    robot_view(&s_robot, now_ms, &view);
    screen_begin_frame(&s_screen, &view, now_ms);
    screen_render_band(&s_screen, s_fb, 0, SIM_H, false);
}

uint16_t *sim_framebuffer(void) { return s_fb; }
const robot_t *sim_robot(void) { return &s_robot; }
const char *sim_state_name(void) { return robot_state_name(s_robot.state); }
