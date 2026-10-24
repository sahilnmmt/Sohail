#include "sohail/robot.h"

#include <stdio.h>
#include <string.h>

#include "sohail/chime.h"

static const char *const STATE_NAMES[] = {
    "boot", "provisioning", "connecting", "idle", "notify", "showing", "pick", "sleep",
};

const char *robot_state_name(robot_state_t s)
{
    return (unsigned)s <= ROBOT_SLEEP ? STATE_NAMES[s] : "?";
}

face_expr_t robot_emoji_face(sohail_emoji_t e)
{
    switch (e) {
    case SOHAIL_EMOJI_HAPPY:  return FACE_HAPPY;
    case SOHAIL_EMOJI_LOVE:   return FACE_LOVE;
    case SOHAIL_EMOJI_LAUGH:  return FACE_LAUGH;
    case SOHAIL_EMOJI_SAD:    return FACE_SAD;
    case SOHAIL_EMOJI_WOW:    return FACE_WOW;
    case SOHAIL_EMOJI_SLEEPY: return FACE_SLEEPY;
    default:                  return FACE_NEUTRAL;
    }
}

void robot_init(robot_t *r, const char *self_id, uint32_t now_ms)
{
    memset(r, 0, sizeof(*r));
    r->state = ROBOT_BOOT;
    r->state_since = now_ms;
    r->last_activity = now_ms;
    snprintf(r->self_id, sizeof(r->self_id), "%s", self_id ? self_id : "");
}

static void enter(robot_t *r, robot_state_t s, uint32_t now)
{
    r->state = s;
    r->state_since = now;
}

static void react(robot_t *r, face_expr_t face, const char *title, uint32_t now)
{
    r->reacting = true;
    r->react_face = face;
    snprintf(r->react_title, sizeof(r->react_title), "%s", title ? title : "");
    r->react_until = now + ROBOT_REACT_MS;
}

static void chime(robot_actions_t *act, int c)
{
    act->flags |= ACT_CHIME;
    act->chime = c;
}

static bool seen_before(robot_t *r, const char *id)
{
    for (int i = 0; i < ROBOT_SEEN_IDS; i++) {
        if (strcmp(r->seen[i], id) == 0) {
            return true;
        }
    }
    snprintf(r->seen[r->seen_next], sizeof(r->seen[0]), "%s", id);
    r->seen_next = (uint8_t)((r->seen_next + 1) % ROBOT_SEEN_IDS);
    return false;
}

static void inbox_push(robot_t *r, const sohail_msg_t *m)
{
    if (r->inbox_count == ROBOT_INBOX_LEN) {
        /* Full: drop the oldest, the newest message matters more. */
        r->inbox_head = (uint8_t)((r->inbox_head + 1) % ROBOT_INBOX_LEN);
        r->inbox_count--;
        r->dropped++;
    }
    r->inbox[(r->inbox_head + r->inbox_count) % ROBOT_INBOX_LEN] = *m;
    r->inbox_count++;
}

static bool inbox_pop(robot_t *r, sohail_msg_t *out)
{
    if (r->inbox_count == 0) {
        return false;
    }
    *out = r->inbox[r->inbox_head];
    r->inbox_head = (uint8_t)((r->inbox_head + 1) % ROBOT_INBOX_LEN);
    r->inbox_count--;
    return true;
}

static void show_next(robot_t *r, uint32_t now)
{
    if (inbox_pop(r, &r->showing)) {
        enter(r, ROBOT_SHOWING, now);
    } else {
        enter(r, ROBOT_IDLE, now);
    }
}

static void enter_ready(robot_t *r, uint32_t now)
{
    if (r->inbox_count) {
        enter(r, ROBOT_NOTIFY, now);
        r->last_remind = now;
    } else {
        enter(r, ROBOT_IDLE, now);
    }
}

static void try_send(robot_t *r, sohail_msg_type_t type, sohail_emoji_t emoji, uint32_t now,
                     robot_actions_t *act)
{
    if (!r->cloud_up) {
        react(r, FACE_SAD, "Offline", now);
        chime(act, CHIME_ERROR);
        return;
    }
    act->flags |= ACT_SEND;
    act->send_type = type;
    act->send_emoji = emoji;
    chime(act, CHIME_SENT);
    react(r, type == SOHAIL_MSG_NUDGE ? FACE_HAPPY : robot_emoji_face(emoji),
          type == SOHAIL_MSG_NUDGE ? "Nudge sent!" : "Sent!", now);
}

static uint32_t show_duration(const sohail_msg_t *m)
{
    return m->type == SOHAIL_MSG_TEXT ? ROBOT_SHOW_TEXT_MS : ROBOT_SHOW_MS;
}

static void on_msg(robot_t *r, const sohail_msg_t *m, uint32_t now, robot_actions_t *act)
{
    if (strcmp(m->from, r->self_id) == 0 || seen_before(r, m->id)) {
        return; /* our own group echo, or an MQTT redelivery */
    }
    inbox_push(r, m);
    switch (r->state) {
    case ROBOT_IDLE:
    case ROBOT_SLEEP:
        r->reacting = false;
        enter(r, ROBOT_NOTIFY, now);
        r->last_remind = now;
        chime(act, CHIME_MESSAGE);
        break;
    case ROBOT_NOTIFY:
        r->last_remind = now;
        chime(act, CHIME_MESSAGE);
        break;
    default:
        break; /* queued; shown after the current message or picker */
    }
}

static void on_input(robot_t *r, robot_event_type_t t, uint32_t now, robot_actions_t *act)
{
    switch (r->state) {
    case ROBOT_SLEEP:
        enter_ready(r, now); /* any input just wakes the robot */
        break;
    case ROBOT_IDLE:
        if (t == EV_BTN_SHORT) {
            try_send(r, SOHAIL_MSG_NUDGE, SOHAIL_EMOJI_HAPPY, now, act);
        } else if (t == EV_BTN_DOUBLE) {
            r->reacting = false;
            r->pick = SOHAIL_EMOJI_HAPPY;
            enter(r, ROBOT_PICK, now);
        } else if (t == EV_TOUCH) {
            react(r, FACE_HAPPY, "", now);
            chime(act, CHIME_HAPPY);
        }
        break;
    case ROBOT_NOTIFY:
        show_next(r, now);
        break;
    case ROBOT_SHOWING:
        if (t == EV_BTN_DOUBLE) {
            r->pick = SOHAIL_EMOJI_LOVE; /* replying: start on love */
            enter(r, ROBOT_PICK, now);
        } else {
            show_next(r, now);
        }
        break;
    case ROBOT_PICK:
        if (t == EV_BTN_SHORT) {
            r->pick = (sohail_emoji_t)((r->pick + 1) % SOHAIL_EMOJI_COUNT);
            r->state_since = now; /* restart the timeout */
        } else {
            sohail_emoji_t e = r->pick;
            enter_ready(r, now);
            try_send(r, SOHAIL_MSG_EMOJI, e, now, act);
        }
        break;
    default:
        break; /* boot / provisioning / connecting ignore gestures */
    }
}

void robot_handle(robot_t *r, const robot_event_t *ev, uint32_t now, robot_actions_t *act)
{
    memset(act, 0, sizeof(*act));

    switch (ev->type) {
    case EV_PROV_START:
        r->wifi_up = r->cloud_up = false;
        snprintf(r->prov_code, sizeof(r->prov_code), "%s", ev->prov_code);
        enter(r, ROBOT_PROVISIONING, now);
        break;
    case EV_PROV_FAIL:
        react(r, FACE_SAD, "Wi-Fi failed", now);
        chime(act, CHIME_ERROR);
        break;
    case EV_WIFI_UP:
        r->wifi_up = true;
        if (r->state == ROBOT_BOOT || r->state == ROBOT_PROVISIONING) {
            enter(r, ROBOT_CONNECTING, now);
        }
        break;
    case EV_WIFI_DOWN:
        r->wifi_up = r->cloud_up = false;
        if (r->state == ROBOT_BOOT) {
            enter(r, ROBOT_CONNECTING, now);
        }
        break;
    case EV_CLOUD_UP:
        r->cloud_up = true;
        r->offline_mode = false;
        if (r->state == ROBOT_BOOT || r->state == ROBOT_CONNECTING) {
            enter_ready(r, now);
            chime(act, CHIME_BOOT);
        }
        break;
    case EV_CLOUD_DOWN:
        r->cloud_up = false;
        break;
    case EV_MSG:
        r->last_activity = now;
        on_msg(r, &ev->msg, now, act);
        break;
    case EV_BTN_SHORT:
    case EV_BTN_DOUBLE:
    case EV_TOUCH:
        r->last_activity = now;
        on_input(r, ev->type, now, act);
        break;
    case EV_BTN_HOLD:
        r->last_activity = now;
        r->reset_warning = true;
        break;
    case EV_BTN_HOLD_RELEASED:
        r->reset_warning = false;
        break;
    case EV_BTN_LONG:
        r->reset_warning = false;
        act->flags |= ACT_FACTORY_RESET;
        break;
    case EV_SEND_FAILED:
        react(r, FACE_SAD, "Not sent", now);
        chime(act, CHIME_ERROR);
        break;
    case EV_TICK:
        break;
    }

    /* Timers. Every event doubles as a tick. */
    if (r->reacting && (int32_t)(now - r->react_until) >= 0) {
        r->reacting = false;
    }
    uint32_t in_state = now - r->state_since;
    switch (r->state) {
    case ROBOT_CONNECTING:
        if (in_state >= ROBOT_CONNECT_TIMEOUT_MS) {
            r->offline_mode = true; /* never a brick: carry on as a companion */
            enter_ready(r, now);
        }
        break;
    case ROBOT_IDLE:
        if (r->inbox_count) {
            enter(r, ROBOT_NOTIFY, now);
            r->last_remind = now;
        } else if (!r->reacting && now - r->last_activity >= ROBOT_SLEEP_AFTER_MS) {
            enter(r, ROBOT_SLEEP, now);
        }
        break;
    case ROBOT_NOTIFY:
        if (now - r->last_remind >= ROBOT_REMIND_MS) {
            r->last_remind = now;
            chime(act, CHIME_MESSAGE);
        }
        break;
    case ROBOT_SHOWING:
        if (in_state >= show_duration(&r->showing)) {
            show_next(r, now);
        }
        break;
    case ROBOT_PICK:
        if (in_state >= ROBOT_PICK_TIMEOUT_MS) {
            enter_ready(r, now);
        }
        break;
    default:
        break;
    }
}

static const char *sender(const sohail_msg_t *m)
{
    return m->name[0] ? m->name : m->from;
}

void robot_view(const robot_t *r, uint32_t now, robot_view_t *v)
{
    memset(v, 0, sizeof(*v));
    v->wifi_up = r->wifi_up;
    v->cloud_up = r->cloud_up;
    v->unread = r->inbox_count;
    v->face = FACE_NEUTRAL;

    switch (r->state) {
    case ROBOT_BOOT:
        v->face = FACE_THINKING;
        snprintf(v->title, sizeof(v->title), "Starting...");
        break;
    case ROBOT_PROVISIONING:
        v->face = FACE_NEUTRAL;
        v->show_code = true;
        snprintf(v->code, sizeof(v->code), "%s", r->prov_code);
        snprintf(v->title, sizeof(v->title), "Setup mode");
        snprintf(v->body, sizeof(v->body), "Open the app and enter this code");
        break;
    case ROBOT_CONNECTING:
        v->face = FACE_THINKING;
        snprintf(v->title, sizeof(v->title), r->wifi_up ? "Connecting..." : "Finding Wi-Fi...");
        break;
    case ROBOT_IDLE:
        if (r->offline_mode && !r->cloud_up) {
            snprintf(v->title, sizeof(v->title), "Offline");
        }
        break;
    case ROBOT_NOTIFY: {
        const sohail_msg_t *m = &r->inbox[r->inbox_head];
        v->face = FACE_EXCITED;
        snprintf(v->title, sizeof(v->title), "%u new", (unsigned)r->inbox_count);
        snprintf(v->body, sizeof(v->body), "From %s - tap to see", sender(m));
        break;
    }
    case ROBOT_SHOWING: {
        const sohail_msg_t *m = &r->showing;
        snprintf(v->title, sizeof(v->title), "%s", sender(m));
        if (m->type == SOHAIL_MSG_NUDGE) {
            v->face = FACE_LOVE;
            snprintf(v->body, sizeof(v->body), "is thinking of you");
        } else if (m->type == SOHAIL_MSG_EMOJI) {
            v->face = robot_emoji_face(m->emoji);
            snprintf(v->body, sizeof(v->body), "sent %s", sohail_emoji_name(m->emoji));
        } else {
            v->face = FACE_HAPPY;
            snprintf(v->body, sizeof(v->body), "%s", m->text);
        }
        break;
    }
    case ROBOT_PICK:
        v->face = robot_emoji_face(r->pick);
        snprintf(v->title, sizeof(v->title), "Send: %s", sohail_emoji_name(r->pick));
        snprintf(v->body, sizeof(v->body), "Press: next  Double: send");
        break;
    case ROBOT_SLEEP:
        v->face = FACE_SLEEPY;
        break;
    }

    bool reaction_visible = r->reacting && (int32_t)(now - r->react_until) < 0 &&
                            (r->state == ROBOT_IDLE || r->state == ROBOT_NOTIFY ||
                             r->state == ROBOT_PROVISIONING || r->state == ROBOT_CONNECTING);
    if (reaction_visible) {
        v->face = r->react_face;
        if (r->react_title[0]) {
            snprintf(v->title, sizeof(v->title), "%s", r->react_title);
        }
    }
    if (r->reset_warning) {
        v->face = FACE_WOW;
        snprintf(v->title, sizeof(v->title), "Hold 10s: reset");
    }
}
