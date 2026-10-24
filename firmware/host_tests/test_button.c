#include "sohail/button.h"
#include "test.h"

static button_t b;
static uint32_t now;

/* Holds the pin at `pressed` for ms, returns the first non-NONE event. */
static button_event_t hold(bool pressed, uint32_t ms)
{
    button_event_t got = BUTTON_NONE;
    for (uint32_t end = now + ms; now < end; now += 10) {
        button_event_t e = button_update(&b, pressed, now);
        if (e != BUTTON_NONE && got == BUTTON_NONE) got = e;
    }
    return got;
}

static void short_press(void)
{
    button_init(&b);
    now = 100;
    CHECK_EQ_INT(hold(true, 120), BUTTON_NONE);
    CHECK_EQ_INT(hold(false, 500), BUTTON_SHORT);
}

static void double_press(void)
{
    button_init(&b);
    now = 100;
    hold(true, 100);
    CHECK_EQ_INT(hold(false, 150), BUTTON_NONE);
    hold(true, 100);
    CHECK_EQ_INT(hold(false, 500), BUTTON_DOUBLE);
}

static void slow_presses_are_two_shorts(void)
{
    button_init(&b);
    now = 100;
    hold(true, 100);
    CHECK_EQ_INT(hold(false, 600), BUTTON_SHORT);
    hold(true, 100);
    CHECK_EQ_INT(hold(false, 600), BUTTON_SHORT);
}

static void bounce_is_filtered(void)
{
    button_init(&b);
    now = 100;
    for (int i = 0; i < 5; i++) { /* 10 ms chatter never stabilises */
        button_update(&b, true, now); now += 10;
        button_update(&b, false, now); now += 10;
    }
    CHECK_EQ_INT(hold(false, 600), BUTTON_NONE);
}

static void hold_then_release_cancels(void)
{
    button_init(&b);
    now = 100;
    CHECK_EQ_INT(hold(true, BUTTON_HOLD_MS + 100), BUTTON_HOLD);
    CHECK_EQ_INT(hold(false, 600), BUTTON_HOLD_RELEASED);
}

static void long_press(void)
{
    button_init(&b);
    now = 100;
    CHECK_EQ_INT(hold(true, BUTTON_HOLD_MS + 100), BUTTON_HOLD);
    CHECK_EQ_INT(hold(true, BUTTON_LONG_MS), BUTTON_LONG);
    CHECK_EQ_INT(hold(true, 2000), BUTTON_NONE); /* fires once */
    CHECK_EQ_INT(hold(false, 600), BUTTON_NONE);
}

int main(void)
{
    RUN(short_press);
    RUN(double_press);
    RUN(slow_presses_are_two_shorts);
    RUN(bounce_is_filtered);
    RUN(hold_then_release_cancels);
    RUN(long_press);
    TEST_EXIT();
}
