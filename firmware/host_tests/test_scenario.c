/*
 * End-to-end "test run" of the robot: boot, BLE setup, connecting, receiving
 * and replying to messages, the emoji picker, going offline and sleeping.
 * Drives the same state machine and screen renderer as the firmware through
 * the simulator, checking behaviour at every step.
 *
 *   test_scenario [frames_dir]   also writes one PPM storyboard frame per step
 */
#include <stdio.h>

#include "../sim/sim.h"
#include "sohail/chime.h"
#include "test.h"

static uint32_t now;
static const char *frames_dir;
static int frame_no;
static int sends, chimes;

static void account(uint32_t flags)
{
    if (flags & ACT_SEND) sends++;
    if (flags & ACT_CHIME) chimes++;
}

/* Let time pass at the firmware's rates: 50 ms robot ticks, 25 fps frames.
 * Only the last second is rendered; earlier frames would not change the
 * outcome (the face animation catches up within a few hundred ms). */
static void run(uint32_t ms)
{
    for (uint32_t t = 0; t < ms; t += 10) {
        now += 10;
        if (now % 50 == 0) account(sim_tick(now));
        if (now % 40 == 0 && ms - t <= 1000) sim_render(now);
    }
}

static void post(robot_event_type_t type)
{
    account(sim_post(type, now));
    run(400); /* let the face ease into its new expression */
}

static void snap(const char *label)
{
    sim_render(now);
    if (!frames_dir) return;
    char path[512];
    snprintf(path, sizeof(path), "%s/step_%02d_%s.ppm", frames_dir, ++frame_no, label);
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); g_failures++; return; }
    fprintf(f, "P6\n%d %d\n255\n", SIM_W, SIM_H);
    const uint16_t *fb = sim_framebuffer();
    for (int i = 0; i < SIM_W * SIM_H; i++) {
        unsigned char rgb[3] = {(unsigned char)((fb[i] >> 8) & 0xF8), (unsigned char)((fb[i] >> 3) & 0xFC),
                                (unsigned char)((fb[i] << 3) & 0xF8)};
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
}

static robot_view_t view(void)
{
    robot_view_t v;
    robot_view(sim_robot(), now, &v);
    return v;
}

static int lit_pixels(void)
{
    int n = 0;
    for (int i = 0; i < SIM_W * SIM_H; i++) n += sim_framebuffer()[i] != 0;
    return n;
}

static void journey(void)
{
    now = 1000;
    sim_init(1234, now);
    run(500);
    CHECK_STR(sim_state_name(), "boot");
    snap("boot");

    /* 1. First boot: no Wi-Fi saved, BLE setup with an on-screen code. */
    account(sim_start_provisioning("482913", now));
    run(600);
    CHECK_STR(sim_state_name(), "provisioning");
    CHECK(view().show_code);
    CHECK_STR(view().code, "482913");
    snap("setup_code");

    /* 2. Wrong password once, then the app sends good credentials. */
    post(EV_PROV_FAIL);
    CHECK_STR(view().title, "Wi-Fi failed");
    snap("wifi_failed");
    run(2000);
    post(EV_WIFI_UP);
    CHECK_STR(sim_state_name(), "connecting");
    snap("connecting");
    post(EV_CLOUD_UP);
    CHECK_STR(sim_state_name(), "idle");
    CHECK(view().cloud_up);
    run(1500);
    snap("idle_online");

    /* 3. Grandma sends a nudge: notify, then tap to see it. */
    int before = chimes;
    account(sim_receive(SOHAIL_MSG_NUDGE, 0, "Grandma", NULL, now));
    CHECK(chimes == before + 1 && sim_last_chime() == CHIME_MESSAGE);
    run(600);
    CHECK_STR(sim_state_name(), "notify");
    CHECK_STR(view().body, "From Grandma - tap to see");
    snap("new_message");
    post(EV_TOUCH);
    CHECK_STR(sim_state_name(), "showing");
    CHECK_EQ_INT(view().face, FACE_LOVE);
    snap("nudge_from_grandma");

    /* 4. Reply with an emoji: double-press, cycle to "laugh", double-press to send. */
    post(EV_BTN_DOUBLE);
    CHECK_STR(sim_state_name(), "pick");
    post(EV_BTN_SHORT); /* love -> laugh */
    CHECK_STR(view().title, "Send: laugh");
    snap("emoji_picker");
    int sent = sends;
    post(EV_BTN_DOUBLE);
    CHECK_EQ_INT(sends, sent + 1);
    CHECK_EQ_INT(sim_last_send_type(), SOHAIL_MSG_EMOJI);
    CHECK_EQ_INT(sim_last_send_emoji(), SOHAIL_EMOJI_LAUGH);
    CHECK_STR(view().title, "Sent!");
    snap("reply_sent");
    run(3000);
    CHECK_STR(sim_state_name(), "idle");

    /* 5. A text from Mum, then a "wow" reaction queued behind it. */
    account(sim_receive(SOHAIL_MSG_TEXT, 0, "Mum", "Dinner is ready! Come down in 5 minutes please", now));
    account(sim_receive(SOHAIL_MSG_EMOJI, SOHAIL_EMOJI_WOW, "Ali", NULL, now));
    run(500);
    CHECK_EQ_INT(view().unread, 2);
    snap("two_unread");
    post(EV_BTN_SHORT);
    CHECK_STR(view().title, "Mum");
    snap("text_from_mum");
    run(ROBOT_SHOW_TEXT_MS);
    CHECK_STR(view().title, "Ali");
    CHECK_EQ_INT(view().face, FACE_WOW);
    snap("wow_from_ali");
    run(ROBOT_SHOW_MS);
    CHECK_STR(sim_state_name(), "idle");

    /* 6. Petting the head. */
    post(EV_TOUCH);
    CHECK_EQ_INT(view().face, FACE_HAPPY);
    CHECK_EQ_INT(sim_last_chime(), CHIME_HAPPY);
    snap("petted");
    run(3000);

    /* 7. Broker goes away: nudges fail gracefully, the face keeps working. */
    post(EV_CLOUD_DOWN);
    sent = sends;
    post(EV_BTN_SHORT);
    CHECK_EQ_INT(sends, sent);
    CHECK_STR(view().title, "Offline");
    CHECK_EQ_INT(view().face, FACE_SAD);
    snap("offline_nudge");
    post(EV_CLOUD_UP);
    run(3000);

    /* 8. Nobody around for 5 minutes: falls asleep; a press wakes it. */
    run(ROBOT_SLEEP_AFTER_MS + 1000);
    CHECK_STR(sim_state_name(), "sleep");
    snap("asleep");
    post(EV_BTN_SHORT);
    CHECK_STR(sim_state_name(), "idle");
    CHECK_EQ_INT(sends, sent); /* waking does not send */

    /* 9. Holding the button shows the reset warning; releasing cancels. */
    post(EV_BTN_HOLD);
    CHECK_STR(view().title, "Hold 10s: reset");
    snap("reset_warning");
    post(EV_BTN_HOLD_RELEASED);
    CHECK_STR(view().title, "");

    CHECK(lit_pixels() > 500); /* the face is still being drawn */
    printf("journey: %d frames, %d messages sent, %d chimes\n", frame_no, sends, chimes);
}

int main(int argc, char **argv)
{
    frames_dir = argc > 1 ? argv[1] : NULL;
    RUN(journey);
    TEST_EXIT();
}
