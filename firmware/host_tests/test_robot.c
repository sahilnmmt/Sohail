#include "sohail/chime.h"
#include "sohail/robot.h"
#include "test.h"

static uint32_t now;
static robot_actions_t act;

static void ev(robot_t *r, robot_event_type_t t)
{
    robot_event_t e = {.type = t};
    robot_handle(r, &e, now, &act);
}

static void advance(robot_t *r, uint32_t ms)
{
    /* Tick in 50 ms steps like the firmware's robot task. */
    for (uint32_t elapsed = 0; elapsed < ms; elapsed += 50) {
        now += 50;
        ev(r, EV_TICK);
    }
}

static int seq;

static void msg(robot_t *r, const char *from, sohail_msg_type_t type)
{
    robot_event_t e = {.type = EV_MSG};
    snprintf(e.msg.id, sizeof(e.msg.id), "m%d", ++seq);
    snprintf(e.msg.from, sizeof(e.msg.from), "%s", from);
    strcpy(e.msg.name, "Nana");
    e.msg.type = type;
    e.msg.emoji = SOHAIL_EMOJI_LAUGH;
    strcpy(e.msg.text, "hello there");
    robot_handle(r, &e, now, &act);
}

static void online(robot_t *r)
{
    now = 1000;
    robot_init(r, "self", now);
    ev(r, EV_WIFI_UP);
    ev(r, EV_CLOUD_UP);
}

static void boot_to_idle(void)
{
    robot_t r;
    now = 1000;
    robot_init(&r, "self", now);
    CHECK_EQ_INT(r.state, ROBOT_BOOT);
    ev(&r, EV_WIFI_UP);
    CHECK_EQ_INT(r.state, ROBOT_CONNECTING);
    ev(&r, EV_CLOUD_UP);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
    CHECK(act.flags & ACT_CHIME);
    CHECK_EQ_INT(act.chime, CHIME_BOOT);
}

static void provisioning_flow(void)
{
    robot_t r;
    now = 1000;
    robot_init(&r, "self", now);
    robot_event_t start = {.type = EV_PROV_START, .prov_code = "123456"};
    robot_handle(&r, &start, now, &act);
    CHECK_EQ_INT(r.state, ROBOT_PROVISIONING);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK(v.show_code);
    CHECK_STR(v.code, "123456");

    ev(&r, EV_PROV_FAIL);
    CHECK_EQ_INT(r.state, ROBOT_PROVISIONING);
    CHECK_EQ_INT(act.chime, CHIME_ERROR);
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "Wi-Fi failed");
    CHECK_EQ_INT(v.face, FACE_SAD);

    ev(&r, EV_BTN_SHORT); /* ignored while provisioning */
    CHECK_EQ_INT(act.flags, 0);

    ev(&r, EV_WIFI_UP);
    ev(&r, EV_CLOUD_UP);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
}

static void connect_timeout_goes_offline(void)
{
    robot_t r;
    now = 1000;
    robot_init(&r, "self", now);
    ev(&r, EV_WIFI_DOWN);
    CHECK_EQ_INT(r.state, ROBOT_CONNECTING);
    advance(&r, ROBOT_CONNECT_TIMEOUT_MS + 100);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
    CHECK(r.offline_mode);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "Offline");

    ev(&r, EV_BTN_SHORT); /* nudge while offline: no send, error feedback */
    CHECK(!(act.flags & ACT_SEND));
    CHECK_EQ_INT(act.chime, CHIME_ERROR);

    ev(&r, EV_WIFI_UP);
    ev(&r, EV_CLOUD_UP);
    CHECK(!r.offline_mode);
}

static void message_notify_show_idle(void)
{
    robot_t r;
    online(&r);
    msg(&r, "nana-1", SOHAIL_MSG_NUDGE);
    CHECK_EQ_INT(r.state, ROBOT_NOTIFY);
    CHECK_EQ_INT(act.chime, CHIME_MESSAGE);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_EQ_INT(v.face, FACE_EXCITED);
    CHECK_EQ_INT(v.unread, 1);
    CHECK_STR(v.body, "From Nana - tap to see");

    ev(&r, EV_TOUCH);
    CHECK_EQ_INT(r.state, ROBOT_SHOWING);
    robot_view(&r, now, &v);
    CHECK_EQ_INT(v.face, FACE_LOVE);
    CHECK_STR(v.title, "Nana");
    CHECK_STR(v.body, "is thinking of you");

    advance(&r, ROBOT_SHOW_MS + 100);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
}

static void queue_plays_in_order(void)
{
    robot_t r;
    online(&r);
    msg(&r, "nana-1", SOHAIL_MSG_EMOJI);
    msg(&r, "nana-1", SOHAIL_MSG_TEXT);
    CHECK_EQ_INT(r.inbox_count, 2);
    ev(&r, EV_BTN_SHORT);
    CHECK_EQ_INT(r.showing.type, SOHAIL_MSG_EMOJI);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_EQ_INT(v.face, FACE_LAUGH);
    CHECK_STR(v.body, "sent laugh");

    msg(&r, "nana-1", SOHAIL_MSG_NUDGE); /* arrives while showing: queued silently */
    CHECK_EQ_INT(r.state, ROBOT_SHOWING);
    CHECK(!(act.flags & ACT_CHIME));

    ev(&r, EV_BTN_SHORT); /* skip to next */
    CHECK_EQ_INT(r.showing.type, SOHAIL_MSG_TEXT);
    robot_view(&r, now, &v);
    CHECK_STR(v.body, "hello there");
    advance(&r, ROBOT_SHOW_TEXT_MS + 100);
    CHECK_EQ_INT(r.showing.type, SOHAIL_MSG_NUDGE);
    advance(&r, ROBOT_SHOW_MS + 100);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
}

static void ignores_self_and_duplicates(void)
{
    robot_t r;
    online(&r);
    msg(&r, "self", SOHAIL_MSG_NUDGE);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
    CHECK_EQ_INT(r.inbox_count, 0);

    robot_event_t e = {.type = EV_MSG};
    strcpy(e.msg.id, "dup");
    strcpy(e.msg.from, "nana-1");
    robot_handle(&r, &e, now, &act);
    robot_handle(&r, &e, now, &act);
    CHECK_EQ_INT(r.inbox_count, 1);
}

static void inbox_overflow_drops_oldest(void)
{
    robot_t r;
    online(&r);
    for (int i = 0; i < ROBOT_INBOX_LEN + 3; i++) {
        msg(&r, "nana-1", SOHAIL_MSG_NUDGE);
    }
    CHECK_EQ_INT(r.inbox_count, ROBOT_INBOX_LEN);
    CHECK_EQ_INT(r.dropped, 3);
    ev(&r, EV_TOUCH);
    char expect[16];
    snprintf(expect, sizeof(expect), "m%d", seq - ROBOT_INBOX_LEN + 1);
    CHECK_STR(r.showing.id, expect);
}

static void nudge_and_pet(void)
{
    robot_t r;
    online(&r);
    ev(&r, EV_BTN_SHORT);
    CHECK(act.flags & ACT_SEND);
    CHECK_EQ_INT(act.send_type, SOHAIL_MSG_NUDGE);
    CHECK_EQ_INT(act.chime, CHIME_SENT);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "Nudge sent!");
    advance(&r, ROBOT_REACT_MS + 100);
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "");
    CHECK_EQ_INT(v.face, FACE_NEUTRAL);

    ev(&r, EV_TOUCH);
    CHECK_EQ_INT(act.chime, CHIME_HAPPY);
    robot_view(&r, now, &v);
    CHECK_EQ_INT(v.face, FACE_HAPPY);

    ev(&r, EV_SEND_FAILED);
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "Not sent");
}

static void emoji_picker(void)
{
    robot_t r;
    online(&r);
    ev(&r, EV_BTN_DOUBLE);
    CHECK_EQ_INT(r.state, ROBOT_PICK);
    CHECK_EQ_INT(r.pick, SOHAIL_EMOJI_HAPPY);
    ev(&r, EV_BTN_SHORT);
    ev(&r, EV_BTN_SHORT);
    CHECK_EQ_INT(r.pick, SOHAIL_EMOJI_LAUGH);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "Send: laugh");
    CHECK_EQ_INT(v.face, FACE_LAUGH);
    ev(&r, EV_BTN_DOUBLE);
    CHECK(act.flags & ACT_SEND);
    CHECK_EQ_INT(act.send_type, SOHAIL_MSG_EMOJI);
    CHECK_EQ_INT(act.send_emoji, SOHAIL_EMOJI_LAUGH);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);

    for (int i = 0; i < SOHAIL_EMOJI_COUNT; i++) { /* wraps around */
        if (i == 0) ev(&r, EV_BTN_DOUBLE);
        ev(&r, EV_BTN_SHORT);
    }
    CHECK_EQ_INT(r.pick, SOHAIL_EMOJI_HAPPY);
    advance(&r, ROBOT_PICK_TIMEOUT_MS + 100); /* times out without sending */
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
}

static void reply_from_showing(void)
{
    robot_t r;
    online(&r);
    msg(&r, "nana-1", SOHAIL_MSG_NUDGE);
    ev(&r, EV_TOUCH);
    ev(&r, EV_BTN_DOUBLE);
    CHECK_EQ_INT(r.state, ROBOT_PICK);
    CHECK_EQ_INT(r.pick, SOHAIL_EMOJI_LOVE);
    ev(&r, EV_TOUCH);
    CHECK_EQ_INT(act.send_emoji, SOHAIL_EMOJI_LOVE);
}

static void sleep_and_wake(void)
{
    robot_t r;
    online(&r);
    advance(&r, ROBOT_SLEEP_AFTER_MS + 100);
    CHECK_EQ_INT(r.state, ROBOT_SLEEP);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_EQ_INT(v.face, FACE_SLEEPY);

    ev(&r, EV_BTN_SHORT); /* wakes, does not send */
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
    CHECK(!(act.flags & ACT_SEND));

    advance(&r, ROBOT_SLEEP_AFTER_MS + 100);
    msg(&r, "nana-1", SOHAIL_MSG_NUDGE); /* message wakes straight to notify */
    CHECK_EQ_INT(r.state, ROBOT_NOTIFY);
}

static void notify_reminds(void)
{
    robot_t r;
    online(&r);
    msg(&r, "nana-1", SOHAIL_MSG_NUDGE);
    int chimes = 0;
    for (uint32_t end = now + ROBOT_REMIND_MS * 2 + 100; now < end;) {
        now += 50;
        ev(&r, EV_TICK);
        if (act.flags & ACT_CHIME) chimes++;
    }
    CHECK_EQ_INT(chimes, 2);
    CHECK_EQ_INT(r.state, ROBOT_NOTIFY); /* never auto-dismissed */
}

static void factory_reset_gesture(void)
{
    robot_t r;
    online(&r);
    ev(&r, EV_BTN_HOLD);
    robot_view_t v;
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "Hold 10s: reset");
    ev(&r, EV_BTN_HOLD_RELEASED);
    robot_view(&r, now, &v);
    CHECK_STR(v.title, "");
    ev(&r, EV_BTN_HOLD);
    ev(&r, EV_BTN_LONG);
    CHECK(act.flags & ACT_FACTORY_RESET);
}

static void timer_wraparound(void)
{
    robot_t r;
    now = 0xFFFFF000u; /* ~4 s before uint32 wrap */
    robot_init(&r, "self", now);
    ev(&r, EV_WIFI_UP);
    ev(&r, EV_CLOUD_UP);
    msg(&r, "nana-1", SOHAIL_MSG_NUDGE);
    ev(&r, EV_TOUCH);
    advance(&r, ROBOT_SHOW_MS - 500);
    CHECK_EQ_INT(r.state, ROBOT_SHOWING);
    advance(&r, 1000);
    CHECK_EQ_INT(r.state, ROBOT_IDLE);
}

static void time_slightly_backwards_is_harmless(void)
{
    /* An event stamped a few ms before the current state began must not
     * look like a huge elapsed time and fire every timer at once. */
    robot_t r;
    online(&r);
    msg(&r, "nana-1", SOHAIL_MSG_NUDGE);
    ev(&r, EV_TOUCH);
    CHECK_EQ_INT(r.state, ROBOT_SHOWING);
    now -= 10;
    ev(&r, EV_TICK);
    CHECK_EQ_INT(r.state, ROBOT_SHOWING);
    now += 10;
    ev(&r, EV_BTN_DOUBLE);
    now -= 5;
    ev(&r, EV_TICK);
    CHECK_EQ_INT(r.state, ROBOT_PICK);
}

int main(void)
{
    RUN(boot_to_idle);
    RUN(provisioning_flow);
    RUN(connect_timeout_goes_offline);
    RUN(message_notify_show_idle);
    RUN(queue_plays_in_order);
    RUN(ignores_self_and_duplicates);
    RUN(inbox_overflow_drops_oldest);
    RUN(nudge_and_pet);
    RUN(emoji_picker);
    RUN(reply_from_showing);
    RUN(sleep_and_wake);
    RUN(notify_reminds);
    RUN(factory_reset_gesture);
    RUN(timer_wraparound);
    RUN(time_slightly_backwards_is_harmless);
    TEST_EXIT();
}
